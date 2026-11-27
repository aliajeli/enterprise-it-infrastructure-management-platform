[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$stateRoot = Join-Path $env:LOCALAPPDATA "EnterpriseIT\LanPreview"
$pidFile = Join-Path $stateRoot "processes.json"
if (Test-Path -LiteralPath $pidFile) {
    $entries = @(Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json)
    foreach ($entry in $entries) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$entry.pid)" -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }
        if ($process.CommandLine -notlike "*$($entry.expectedCommand)*") {
            Write-Warning "PID $($entry.pid) no longer matches the recorded EnterpriseIT $($entry.role) command; it was not terminated."
            continue
        }
        & taskkill.exe /PID ([string]$entry.pid) /T /F | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "Could not stop process tree for PID $($entry.pid)." }
    }
    Remove-Item -LiteralPath $pidFile -Force
}
Push-Location $repoRoot
try { if (Get-Command docker -ErrorAction SilentlyContinue) { & docker compose stop db; if ($LASTEXITCODE -ne 0) { Write-Warning "Docker database stop returned exit code $LASTEXITCODE." } } }
finally { Pop-Location }
Write-Host "EnterpriseIT LAN preview processes stopped. Database volume and data were preserved."
