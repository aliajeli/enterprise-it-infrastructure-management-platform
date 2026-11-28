[CmdletBinding()]
param([switch]$SkipDependencyInstall,[switch]$SkipBuild,[switch]$BootstrapAdmin,[switch]$ConfigureFirewall)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$envFile = Join-Path $repoRoot ".env"
$envExample = Join-Path $repoRoot ".env.example"
$stateRoot = Join-Path $env:LOCALAPPDATA "EnterpriseIT\LanPreview"
$pidFile = Join-Path $stateRoot "processes.json"
$logRoot = Join-Path $stateRoot "logs"
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Invoke-Checked([string]$File,[string[]]$Arguments,[string]$WorkingDirectory=$repoRoot) {
    Push-Location $WorkingDirectory
    try { & $File @Arguments; if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE." } }
    finally { Pop-Location }
}
function Get-LanIPv4 {
    $candidate = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
        ForEach-Object { $_.IPv4Address } | Where-Object { $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1
    if ($null -eq $candidate) { throw "No active LAN IPv4 address with a default gateway was found." }
    return $candidate.IPAddress
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "compose.yaml"))) { throw "Run this script from a complete EnterpriseIT source checkout." }
if (Test-Path -LiteralPath $pidFile) { throw "A LAN preview session is already recorded. Run stop-lan-preview.ps1 first." }
$nodeVersion = (& node --version).Trim()
if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v26\.') { throw "Node.js 26.x is required; detected '$nodeVersion'." }
$npmVersion = (& npm --version).Trim()
if ($LASTEXITCODE -ne 0 -or [version]$npmVersion -lt [version]"11.0.0") { throw "npm 11.x or newer is required; detected '$npmVersion'." }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker Desktop with Linux containers is required for this first LAN preview." }
Invoke-Checked "docker" @("info")
if (-not (Test-Path -LiteralPath $envFile)) {
    $template = Get-Content -LiteralPath $envExample -Raw
    $bytes = [byte[]]::new(32); $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $password = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
    $template = $template.Replace("replace-this-password", $password)
    [IO.File]::WriteAllText($envFile, $template, [Text.UTF8Encoding]::new($false))
    Write-Host "Created a local .env file with a generated database password."
}
if (-not $SkipDependencyInstall -and -not (Test-Path -LiteralPath (Join-Path $repoRoot "node_modules"))) { Invoke-Checked "npm" @("ci") }
Invoke-Checked "docker" @("compose","up","-d","--wait","db")
Invoke-Checked "npm" @("run","db:validate")
Invoke-Checked "npm" @("run","db:generate")
Invoke-Checked "npm" @("run","db:migrate:deploy")
if (-not $SkipBuild) { Invoke-Checked "npm" @("run","build") }
if ($BootstrapAdmin) { Invoke-Checked "npm" @("run","bootstrap-admin") }
$lanIp = Get-LanIPv4
$env:API_HOST = "127.0.0.1"; $env:API_PORT = "13001"
$env:PUBLIC_ORIGIN = ("http://" + $lanIp + ":3000"); $env:COOKIE_SECURE = "false"
if ($ConfigureFirewall) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run elevated PowerShell to create the optional Private-profile firewall rule." }
    if (-not (Get-NetFirewallRule -DisplayName "EnterpriseIT LAN Preview TCP 3000" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "EnterpriseIT LAN Preview TCP 3000" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3000 -Profile Private -RemoteAddress LocalSubnet | Out-Null
    }
}
$apiLog = Join-Path $logRoot "api.log"; $webLog = Join-Path $logRoot "web.log"
$api = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c","npm run dev:api") -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput $apiLog -RedirectStandardError ($apiLog + ".err") -PassThru
$web = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c","npm exec --workspace @platform/web -- next dev --hostname 0.0.0.0") -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput $webLog -RedirectStandardError ($webLog + ".err") -PassThru
@(
    [pscustomobject]@{ pid = $api.Id; role = "api"; expectedCommand = "npm run dev:api" },
    [pscustomobject]@{ pid = $web.Id; role = "web"; expectedCommand = "next dev --hostname 0.0.0.0" }
) | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $pidFile -Encoding utf8
try {
    $deadline = (Get-Date).AddMinutes(3); $apiReady = $false; $webReady = $false
    while ((Get-Date) -lt $deadline -and (-not $apiReady -or -not $webReady)) {
        if (-not $api.HasExited) { try { $apiReady = (Invoke-WebRequest -Uri "http://127.0.0.1:13001/health/ready" -TimeoutSec 2 -UseBasicParsing).StatusCode -eq 200 } catch {} }
        if (-not $web.HasExited) { try { $webReady = (Invoke-WebRequest -Uri "http://127.0.0.1:3000" -TimeoutSec 2 -UseBasicParsing).StatusCode -in @(200,302,307) } catch {} }
        if (-not $apiReady -or -not $webReady) { Start-Sleep -Seconds 2 }
    }
    if (-not $apiReady -or -not $webReady) { throw "Application readiness check failed. Review logs under $logRoot." }
} catch { & (Join-Path $PSScriptRoot "stop-lan-preview.ps1"); throw }
Write-Host ""
Write-Host "EnterpriseIT LAN preview is running."
Write-Host ("Open from this PC or another computer on the same LAN: http://" + $lanIp + ":3000")
Write-Host "API and PostgreSQL remain loopback-only."
Write-Host "Logs: $logRoot"
Write-Host "Stop: pwsh -NoProfile -File scripts\windows\stop-lan-preview.ps1"
if (-not $ConfigureFirewall) { Write-Host "If LAN clients cannot connect, allow inbound TCP 3000 on the Windows Private profile (LocalSubnet only)." }
