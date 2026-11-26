[CmdletBinding()]
param(
    [ValidateRange(1, 1024)]
    [int]$MinimumFreeSpaceGB = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-InstallerPreflightFacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Facts,
        [ValidateRange(1, 1024)]
        [int]$MinimumFreeSpaceGB = 10
    )

    $checks = [System.Collections.Generic.List[object]]::new()
    $minimumBytes = [int64]$MinimumFreeSpaceGB * 1GB

    $checks.Add([pscustomobject]@{
        id = "windows"
        required = $true
        passed = [bool]$Facts.IsWindows
        detail = if ($Facts.IsWindows) { "Windows operating system detected." } else { "This preflight is supported only on Windows." }
    })
    # This is a baseline OS-family check, not an approved support matrix.
    # Treat missing facts as false, never as implicit support.
    $isServer = $null -ne $Facts.PSObject.Properties['IsWindowsServer'] -and [bool]$Facts.IsWindowsServer
    $architecture = if ($null -ne $Facts.PSObject.Properties['OSArchitecture']) { [string]$Facts.OSArchitecture } else { 'Unknown' }
    $isX64 = [bool]$Facts.Is64BitOS -and $architecture -ceq 'X64'
    $checks.Add([pscustomobject]@{
        id = "windows-server"
        required = $true
        passed = $isServer
        detail = if ($isServer) { "Windows Server family detected; version support is not yet established." } else { "A Windows Server operating system is required." }
    })
    $checks.Add([pscustomobject]@{
        id = "architecture"
        required = $true
        passed = $isX64
        detail = if ($isX64) { "x64 operating system detected." } else { "An x64 operating system is required; x86 and ARM64 are not supported by this payload." }
    })
    $checks.Add([pscustomobject]@{
        id = "elevation"
        required = $true
        passed = [bool]$Facts.IsElevated
        detail = if ($Facts.IsElevated) { "The current process is elevated." } else { "Run this check from an elevated PowerShell session." }
    })

    $locations = @($Facts.Locations)
    foreach ($name in @("ProgramFiles", "ProgramData")) {
        $location = $locations | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($null -eq $location) {
            $checks.Add([pscustomobject]@{
                id = "storage-$name"
                required = $true
                passed = $false
                detail = "The $name installation location could not be inspected."
            })
            continue
        }

        $isLocalFixed = ($location.DriveType -eq "Fixed") -and [bool]$location.IsReady
        $hasSpace = [int64]$location.FreeBytes -ge $minimumBytes
        $passed = $isLocalFixed -and $hasSpace
        $freeGB = [math]::Round(([double]$location.FreeBytes / 1GB), 2)
        $detail = if (-not $isLocalFixed) {
            "$name must resolve to a ready local fixed drive."
        } elseif (-not $hasSpace) {
            "$name volume has $freeGB GB free; at least $MinimumFreeSpaceGB GB is required by this preflight."
        } else {
            "$name volume is a ready local fixed drive with $freeGB GB free."
        }
        $checks.Add([pscustomobject]@{
            id = "storage-$name"
            required = $true
            passed = $passed
            detail = $detail
        })
    }

    $failed = @($checks | Where-Object { $_.required -and -not $_.passed })
    $hostReady = ($failed.Count -eq 0)
    # Product readiness is a capability gate, not a constant: the blocker
    # list IS the gate, and a blocker is removed only when its capability is
    # implemented and its test suite is green. Credential transport, cluster
    # ownership, bootstrap, orchestration and offline installation are
    # approved (CI-proven); migration transport and the Windows Server
    # security acceptance remain open.
    $installationBlockers = @(
        "PostgreSQL migration credential transport is not approved.",
        "Security review and supported Windows Server acceptance are incomplete."
    )
    return [pscustomobject]@{
        schemaVersion = 2
        # Host checks are necessary but not sufficient for product
        # readiness. The offline installer stages on hostReady; every
        # remaining blocker stays enforced at its own fail-closed layer
        # (the migration entry point refuses, orchestration rolls back the
        # services it started, and Setup.exe will consume full ready).
        hostReady = $hostReady
        ready = ($hostReady -and $installationBlockers.Count -eq 0)
        readinessScope = "host-baseline-only"
        installationBlockers = $installationBlockers
        minimumFreeSpaceGB = $MinimumFreeSpaceGB
        checks = @($checks.ToArray())
    }
}

function Get-InstallerPreflightFacts {
    [CmdletBinding()]
    param()

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $locations = [System.Collections.Generic.List[object]]::new()

    foreach ($entry in @(
        @{ Name = "ProgramFiles"; Path = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles) },
        @{ Name = "ProgramData"; Path = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData) }
    )) {
        $pathRoot = [System.IO.Path]::GetPathRoot($entry.Path)
        $drive = [System.IO.DriveInfo]::new($pathRoot)
        $freeBytes = if ($drive.IsReady) { [int64]$drive.AvailableFreeSpace } else { [int64]0 }
        $locations.Add([pscustomobject]@{
            Name = $entry.Name
            Path = $entry.Path
            DriveType = [string]$drive.DriveType
            IsReady = [bool]$drive.IsReady
            FreeBytes = $freeBytes
        })
    }

    return [pscustomobject]@{
        IsWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
        Is64BitOS = [Environment]::Is64BitOperatingSystem
        OSArchitecture = [string][Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        IsWindowsServer = ([int]$os.ProductType -in @(2,3))
        IsElevated = $isElevated
        OsCaption = [string]$os.Caption
        OsVersion = [string]$os.Version
        OsBuild = [string]$os.BuildNumber
        Locations = @($locations.ToArray())
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    $facts = Get-InstallerPreflightFacts
    $report = Test-InstallerPreflightFacts -Facts $facts -MinimumFreeSpaceGB $MinimumFreeSpaceGB
    $report | Add-Member -NotePropertyName operatingSystem -NotePropertyValue $facts.OsCaption
    $report | Add-Member -NotePropertyName osVersion -NotePropertyValue $facts.OsVersion
    $report | Add-Member -NotePropertyName osBuild -NotePropertyValue $facts.OsBuild
    $report | ConvertTo-Json -Depth 6
    # A valid host baseline is not installer readiness. Keep the exit status
    # fail-closed while the installation blockers remain open.
    if (-not $report.ready) {
        exit 2
    }
}
