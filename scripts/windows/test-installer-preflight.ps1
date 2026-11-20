$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "installer-preflight.ps1")

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-TestFacts {
    param(
        [bool]$IsWindows = $true,
        [bool]$Is64BitOS = $true,
        [bool]$IsElevated = $true,
        [string]$ProgramFilesDriveType = "Fixed",
        [int64]$ProgramFilesFreeBytes = 20GB,
        [string]$ProgramDataDriveType = "Fixed",
        [int64]$ProgramDataFreeBytes = 20GB
    )
    return [pscustomobject]@{
        IsWindows = $IsWindows
        Is64BitOS = $Is64BitOS
        IsElevated = $IsElevated
        Locations = @(
            [pscustomobject]@{ Name = "ProgramFiles"; DriveType = $ProgramFilesDriveType; IsReady = $true; FreeBytes = $ProgramFilesFreeBytes },
            [pscustomobject]@{ Name = "ProgramData"; DriveType = $ProgramDataDriveType; IsReady = $true; FreeBytes = $ProgramDataFreeBytes }
        )
    }
}

$minimum = 10
$valid = Test-InstallerPreflightFacts -Facts (New-TestFacts) -MinimumFreeSpaceGB $minimum
Assert-Condition $valid.ready "A valid x64 elevated Windows host should pass."
Assert-Condition ($valid.checks.Count -eq 5) "The preflight should evaluate exactly five required baseline checks."

$notElevated = Test-InstallerPreflightFacts -Facts (New-TestFacts -IsElevated $false) -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $notElevated.ready) "A non-elevated process must fail."

$wrongArchitecture = Test-InstallerPreflightFacts -Facts (New-TestFacts -Is64BitOS $false) -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $wrongArchitecture.ready) "A non-x64 operating system must fail."

$notWindows = Test-InstallerPreflightFacts -Facts (New-TestFacts -IsWindows $false) -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $notWindows.ready) "A non-Windows host must fail."

$lowSpace = Test-InstallerPreflightFacts -Facts (New-TestFacts -ProgramDataFreeBytes 1GB) -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $lowSpace.ready) "Insufficient ProgramData space must fail."

$networkVolume = Test-InstallerPreflightFacts -Facts (New-TestFacts -ProgramFilesDriveType "Network") -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $networkVolume.ready) "A network Program Files volume must fail."

$notReady = New-TestFacts
$notReady.Locations[1].IsReady = $false
$unavailableVolume = Test-InstallerPreflightFacts -Facts $notReady -MinimumFreeSpaceGB $minimum
Assert-Condition (-not $unavailableVolume.ready) "An unavailable ProgramData volume must fail."

Write-Output "Installer preflight unit tests passed (7 assertions groups)."
