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
    if (-not (Test-Path -LiteralPath (Join-Path $source "server.js") -PathType Leaf)) {
        throw "Next.js standalone server.js is missing."
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
        if (Test-Path -LiteralPath $plan.StaticSource -PathType Container) {
            $staticTarget = Join-Path $staging ".next\static"
            New-Item -ItemType Directory -Path $staticTarget -Force | Out-Null
            Get-ChildItem -LiteralPath $plan.StaticSource -Force | Copy-Item -Destination $staticTarget -Recurse
        }
        if (Test-Path -LiteralPath $plan.PublicSource -PathType Container) {
            $publicTarget = Join-Path $staging "public"
            New-Item -ItemType Directory -Path $publicTarget -Force | Out-Null
            Get-ChildItem -LiteralPath $plan.PublicSource -Force | Copy-Item -Destination $publicTarget -Recurse
        }
        Copy-Item -LiteralPath $plan.ServiceEntrySource -Destination (Join-Path $staging "service-entry.cjs")
        foreach ($required in @("server.js", "node_modules\next", "service-entry.cjs")) {
            if (-not (Test-Path -LiteralPath (Join-Path $staging $required))) {
                throw "Staged Web payload is incomplete: $required"
            }
        }
        if (Test-Path -LiteralPath $plan.Destination) {
            throw "Web standalone destination appeared during staging; refusing to overwrite."
        }
        [IO.Directory]::Move($staging, $plan.Destination)
        [pscustomobject]@{
            installRoot = $plan.InstallRoot
            destination = $plan.Destination
            staged = $true
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
