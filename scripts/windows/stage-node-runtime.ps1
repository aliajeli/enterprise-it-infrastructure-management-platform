[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
    [Parameter(Mandatory=$true)][string]$NodeRuntimeDirectory,
    [Parameter(Mandatory=$true)][string]$InstallRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NodeRuntimeStagePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$NodeRuntimeDirectory,
        [Parameter(Mandatory=$true)][string]$InstallRoot,
        [Parameter(Mandatory=$true)][string]$NodeVersion
    )
    $source = [IO.Path]::GetFullPath($NodeRuntimeDirectory)
    $root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $programFiles = [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $root.StartsWith(($programFiles + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Install root must be beneath Program Files."
    }
    $parts = $root.Substring($programFiles.Length + 1).Split([IO.Path]::DirectorySeparatorChar)
    if ($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$') {
        throw "Install root must be Program Files\EnterpriseIT\<major.minor.patch>."
    }
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Node runtime source directory does not exist."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $source "node.exe") -PathType Leaf)) {
        throw "Node runtime source must contain node.exe."
    }
    if ($NodeVersion -notmatch '^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$' -or [int]$Matches.major -ne 26) {
        throw "The bundled runtime must be an exact Node.js 26.x version; received '$NodeVersion'."
    }
    $destination = Join-Path $root "runtime"
    if (Test-Path -LiteralPath $destination) {
        throw "Immutable Node runtime destination already exists: $destination"
    }
    [pscustomobject]@{
        SourceDirectory = $source
        InstallRoot = $root
        Destination = $destination
        NodeVersion = $NodeVersion
        NodeMajorVersion = 26
        Immutable = $true
        CopyAllRuntimeFiles = $true
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    $sourceNode = Join-Path ([IO.Path]::GetFullPath($NodeRuntimeDirectory)) "node.exe"
    if (-not (Test-Path -LiteralPath $sourceNode -PathType Leaf)) { throw "Node runtime source must contain node.exe." }
    $versionOutput = (& $sourceNode --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to query the staged Node runtime version." }
    $plan = Get-NodeRuntimeStagePlan -NodeRuntimeDirectory $NodeRuntimeDirectory -InstallRoot $InstallRoot -NodeVersion $versionOutput
    if ($WhatIfPreference) {
        [pscustomobject]@{ installRoot=$plan.InstallRoot; destination=$plan.Destination; nodeVersion=$plan.NodeVersion; copyAllRuntimeFiles=$true; dryRun=$true } | ConvertTo-Json -Depth 4
        return
    }
    if (-not $PSCmdlet.ShouldProcess($plan.Destination, "Stage immutable Node.js runtime $($plan.NodeVersion)")) { return }
    New-Item -ItemType Directory -Path $plan.Destination -Force | Out-Null
    try {
        Get-ChildItem -LiteralPath $plan.SourceDirectory -Force | Copy-Item -Destination $plan.Destination -Recurse -Force
        $stagedNode = Join-Path $plan.Destination "node.exe"
        if (-not (Test-Path -LiteralPath $stagedNode -PathType Leaf)) { throw "Node executable was not staged." }
        $stagedVersion = (& $stagedNode --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $stagedVersion -ne $plan.NodeVersion) {
            throw "Staged Node runtime version mismatch. Expected $($plan.NodeVersion), received $stagedVersion."
        }
        [pscustomobject]@{ installRoot=$plan.InstallRoot; destination=$plan.Destination; nodeVersion=$plan.NodeVersion; staged=$true; immutable=$true } | ConvertTo-Json -Depth 4
    }
    catch {
        if (Test-Path -LiteralPath $plan.Destination) {
            Remove-Item -LiteralPath $plan.Destination -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}
