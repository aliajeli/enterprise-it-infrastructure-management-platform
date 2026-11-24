$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "installer-preflight.ps1")

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-TestFacts {
    param(
        [bool]$WindowsPlatform = $true,
        [bool]$Is64BitOS = $true,
        [string]$OSArchitecture = 'X64',
        [bool]$IsWindowsServer = $true,
        [bool]$IsElevated = $true,
        [string]$ProgramFilesDriveType = "Fixed",
        [int64]$ProgramFilesFreeBytes = 20GB,
        [string]$ProgramDataDriveType = "Fixed",
        [int64]$ProgramDataFreeBytes = 20GB
    )
    return [pscustomobject]@{
        IsWindows = $WindowsPlatform
        Is64BitOS = $Is64BitOS
        OSArchitecture = $OSArchitecture
        IsWindowsServer = $IsWindowsServer
        IsElevated = $IsElevated
        Locations = @(
            [pscustomobject]@{ Name = "ProgramFiles"; DriveType = $ProgramFilesDriveType; IsReady = $true; FreeBytes = $ProgramFilesFreeBytes },
            [pscustomobject]@{ Name = "ProgramData"; DriveType = $ProgramDataDriveType; IsReady = $true; FreeBytes = $ProgramDataFreeBytes }
        )
    }
}

$minimum = 10
$valid = Test-InstallerPreflightFacts -Facts (New-TestFacts) -MinimumFreeSpaceGB $minimum
Assert-Condition $valid.hostReady "A valid x64 elevated Windows Server host should pass baseline checks."
Assert-Condition (-not $valid.ready) "Host preflight must not claim that installation is ready."
Assert-Condition ($valid.schemaVersion -eq 2 -and $valid.readinessScope -eq 'host-baseline-only' -and $valid.installationBlockers.Count -gt 0) "The report must identify its scope and installation blockers."
Assert-Condition ($valid.checks.Count -eq 6) "The preflight should evaluate six required baseline checks."

$notElevated = Test-InstallerPreflightFacts -Facts (New-TestFacts -IsElevated $false) -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $notElevated.hostReady) "A non-elevated process must fail."

$wrongArchitecture = Test-InstallerPreflightFacts -Facts (New-TestFacts -Is64BitOS $false) -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $wrongArchitecture.hostReady) "A non-x64 operating system must fail."

$arm64 = Test-InstallerPreflightFacts -Facts (New-TestFacts -OSArchitecture 'Arm64') -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $arm64.hostReady) "A 64-bit ARM host must not pass the x64 baseline."
$desktop = Test-InstallerPreflightFacts -Facts (New-TestFacts -IsWindowsServer $false) -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $desktop.hostReady) "A Windows desktop must not pass the Server baseline."
$missingArchitecture = New-TestFacts
$missingArchitecture.PSObject.Properties.Remove('OSArchitecture')
$unknown = Test-InstallerPreflightFacts -Facts $missingArchitecture -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $unknown.hostReady) "An unknown architecture must fail closed."
$missingServer = New-TestFacts
$missingServer.PSObject.Properties.Remove('IsWindowsServer')
$unknown = Test-InstallerPreflightFacts -Facts $missingServer -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $unknown.hostReady) "An unknown OS family must fail closed."

$notWindows = Test-InstallerPreflightFacts -Facts (New-TestFacts -WindowsPlatform $false) -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $notWindows.hostReady) "A non-Windows host must fail."

$lowSpace = Test-InstallerPreflightFacts -Facts (New-TestFacts -ProgramDataFreeBytes 1GB) -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $lowSpace.hostReady) "Insufficient ProgramData space must fail."

$networkVolume = Test-InstallerPreflightFacts -Facts (New-TestFacts -ProgramFilesDriveType "Network") -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $networkVolume.hostReady) "A network Program Files volume must fail."

$notReady = New-TestFacts
$notReady.Locations[1].IsReady = $false
$unavailableVolume = Test-InstallerPreflightFacts -Facts $notReady -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $unavailableVolume.hostReady) "An unavailable ProgramData volume must fail."

Write-Output "Installer host-baseline preflight and fail-closed readiness tests passed."
