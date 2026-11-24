[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
    [Parameter(Mandatory=$true)][string]$StandaloneDirectory,
    [Parameter(Mandatory=$true)][string]$InstallRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-WebStandaloneStagePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$StandaloneDirectory,
        [Parameter(Mandatory=$true)][string]$InstallRoot
    )
    $source = [IO.Path]::GetFullPath($StandaloneDirectory)
    $root = [IO.Path]::GetFullPath($InstallRoot)
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Next.js standalone source directory does not exist."
    }
    # Next.js traces this monorepo from the repository root. Its actual
    # standalone entry is apps/web/server.js, not always root/server.js.
    $flatEntry = Join-Path $source "server.js"
    $monorepoEntry = Join-Path $source "apps\web\server.js"
    $flat = Test-Path -LiteralPath $flatEntry -PathType Leaf
    $monorepo = Test-Path -LiteralPath $monorepoEntry -PathType Leaf
    if ($flat -eq $monorepo) { throw "Standalone payload must have exactly one supported Web entry point." }
    $appRelative = if ($monorepo) { "apps\web" } else { "" }
    $appSource = if ($appRelative) { Join-Path $source $appRelative } else { $source }
    if (-not (Test-Path -LiteralPath (Join-Path $appSource ".next\required-server-files.json") -PathType Leaf)) {
        throw "Standalone build-time server configuration is missing."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $source "node_modules\next") -PathType Container)) {
        throw "Standalone Next.js dependencies are incomplete."
    }
    $destination = Join-Path $root "apps\web\.next\standalone"
    if (Test-Path -LiteralPath $destination) {
        throw "Web standalone destination already exists; refusing to overwrite: $destination"
    }
    $sourcePrefix = $source.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $destinationPrefix = $destination.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($destination.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $source.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($source, $destination, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Standalone source and destination must not overlap."
    }
    [pscustomobject]@{
        SourceDirectory = $source
        InstallRoot = $root
        Destination = $destination
        AppRelative = $appRelative
        Layout = if ($monorepo) { "monorepo" } else { "flat" }
        StaticSource = Join-Path (Split-Path $source -Parent) "static"
        PublicSource = Join-Path (Split-Path (Split-Path $source -Parent) -Parent) "public"
        ServiceEntrySource = Join-Path $PSScriptRoot "..\..\apps\web\windows\service-entry.cjs"
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    $plan = Get-WebStandaloneStagePlan -StandaloneDirectory $StandaloneDirectory -InstallRoot $InstallRoot
    if (-not (Test-Path -LiteralPath $plan.ServiceEntrySource -PathType Leaf)) {
        throw "Web service entry point source is missing."
    }
    if ($WhatIfPreference) {
        [pscustomobject]@{
            installRoot = $plan.InstallRoot
            destination = $plan.Destination
            sourceDirectory = $plan.SourceDirectory
            layout = $plan.Layout
            overwrite = $false
            atomicPromotion = $true
            dryRun = $true
        } | ConvertTo-Json -Depth 4
        return
    }
    if (-not $PSCmdlet.ShouldProcess($plan.Destination, "Stage immutable Next.js standalone payload")) { return }

    $parent = Split-Path $plan.Destination -Parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $staging = Join-Path $parent (".standalone.staging." + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $staging -ErrorAction Stop | Out-Null
        Get-ChildItem -LiteralPath $plan.SourceDirectory -Force | Copy-Item -Destination $staging -Recurse
        $stagedApp = if ($plan.AppRelative) { Join-Path $staging $plan.AppRelative } else { $staging }
        if (Test-Path -LiteralPath $plan.StaticSource -PathType Container) {
            $staticTarget = Join-Path $stagedApp ".next\static"
            New-Item -ItemType Directory -Path $staticTarget -Force | Out-Null
            Get-ChildItem -LiteralPath $plan.StaticSource -Force | Copy-Item -Destination $staticTarget -Recurse
        }
        if (Test-Path -LiteralPath $plan.PublicSource -PathType Container) {
            $publicTarget = Join-Path $stagedApp "public"
            New-Item -ItemType Directory -Path $publicTarget -Force | Out-Null
            Get-ChildItem -LiteralPath $plan.PublicSource -Force | Copy-Item -Destination $publicTarget -Recurse
        }
        Copy-Item -LiteralPath $plan.ServiceEntrySource -Destination (Join-Path $staging "service-entry.cjs")
        if (-not (Test-Path -LiteralPath (Join-Path $stagedApp "server.js") -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $staging "node_modules\next") -PathType Container) -or
            -not (Test-Path -LiteralPath (Join-Path $staging "service-entry.cjs") -PathType Leaf)) {
            throw "Staged Web payload is incomplete."
        }
        if (Test-Path -LiteralPath $plan.Destination) {
            throw "Web standalone destination appeared during staging; refusing to overwrite."
        }
        [IO.Directory]::Move($staging, $plan.Destination)
        [pscustomobject]@{
            installRoot = $plan.InstallRoot
            destination = $plan.Destination
            staged = $true
            layout = $plan.Layout
            immutable = $true
            atomicPromotion = $true
        } | ConvertTo-Json -Depth 4
    }
    catch {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}
