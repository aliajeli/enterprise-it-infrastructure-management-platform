$ErrorActionPreference = "Stop"
$paths = @(
    (Join-Path $PSScriptRoot "start-lan-preview.ps1"),
    (Join-Path $PSScriptRoot "stop-lan-preview.ps1")
)
foreach ($path in $paths) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $details = ($errors | ForEach-Object { $_.Message }) -join "; "
        throw "PowerShell syntax errors in '$path': $details"
    }
}
$start = Get-Content -LiteralPath $paths[0] -Raw
$stop = Get-Content -LiteralPath $paths[1] -Raw
foreach ($required in @(
    'API_HOST = "127.0.0.1"',
    'next dev --hostname 0.0.0.0',
    'LocalSubnet',
    'db:validate',
    'db:migrate:deploy',
    'health/ready',
    'COOKIE_SECURE = "false"'
)) {
    if (-not $start.Contains($required)) { throw "LAN launcher is missing required behavior: $required" }
}
if (-not $stop.Contains('docker compose stop db')) { throw "Stop script must stop PostgreSQL without deleting its volume." }
if ($stop.Contains('docker compose down -v')) { throw "Stop script must never delete the preview database volume." }
Write-Host "LAN preview PowerShell syntax and static policy checks passed."
