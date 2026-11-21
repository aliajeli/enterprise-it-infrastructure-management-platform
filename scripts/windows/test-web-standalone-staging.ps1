$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$stageScript = Join-Path $PSScriptRoot "stage-web-standalone.ps1"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("enterpriseit-web-stage-" + [guid]::NewGuid().ToString("N"))
$source = Join-Path $tempRoot "build\.next\standalone"
$installRoot = Join-Path $tempRoot "install"
try {
    New-Item -ItemType Directory -Path (Join-Path $source "node_modules\next"), (Join-Path $tempRoot "build\.next\static"), (Join-Path $tempRoot "build\public"), $installRoot -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source "server.js"), "console.log('next');")
    [IO.File]::WriteAllText((Join-Path $source "node_modules\next\index.js"), "module.exports = {};")
    [IO.File]::WriteAllText((Join-Path $tempRoot "build\.next\static\asset.txt"), "static")
    [IO.File]::WriteAllText((Join-Path $tempRoot "build\public\logo.txt"), "public")

    $dryRun = & $stageScript -StandaloneDirectory $source -InstallRoot $installRoot -WhatIf | ConvertFrom-Json
    $destination = Join-Path $installRoot "apps\web\.next\standalone"
    if (-not $dryRun.dryRun -or $dryRun.overwrite -or (Test-Path -LiteralPath $destination)) {
        throw "Web standalone WhatIf did not remain read-only."
    }

    & $stageScript -StandaloneDirectory $source -InstallRoot $installRoot -Confirm:$false | Out-Null
    foreach ($required in @("server.js", "node_modules\next\index.js", "service-entry.cjs", ".next\static\asset.txt", "public\logo.txt")) {
        if (-not (Test-Path -LiteralPath (Join-Path $destination $required) -PathType Leaf)) {
            throw "Expected staged Web file is missing: $required"
        }
    }

    $rejected = $false
    try { & $stageScript -StandaloneDirectory $source -InstallRoot $installRoot -Confirm:$false | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Existing Web standalone destination was overwritten." }

    $rejected = $false
    try { Get-WebStandaloneStagePlan -StandaloneDirectory $source -InstallRoot $installRoot | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Existing destination was accepted by the stage plan." }
    Write-Host "Web standalone staging policy tests passed."
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
