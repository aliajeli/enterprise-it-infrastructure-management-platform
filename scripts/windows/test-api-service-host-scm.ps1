$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$root = Join-Path $env:RUNNER_TEMP "enterprise-it-api-scm-smoke"
$runtime = Join-Path $root "runtime"
$apiDirectory = Join-Path $root "apps\api\dist"
$serviceName = "EnterpriseITApi"
$hostProject = Join-Path $repoRoot "apps\api\windows\service-host\EnterpriseIT.ApiServiceHost.csproj"
$stubProject = Join-Path $repoRoot "apps\api\windows\service-host-smoke\WindowsApiStub.csproj"
$hostExe = Join-Path $root "EnterpriseIT.ApiServiceHost.exe"
$apiEntry = Join-Path $apiDirectory "server.js"
$serviceCreated = $false

function Invoke-Sc {
    param([string[]] $Arguments)
    & sc.exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "sc.exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE." }
}
function Get-ApiChild {
    return @(Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and $_.CommandLine.Contains($apiEntry, [StringComparison]::OrdinalIgnoreCase)
    })
}

try {
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null
    New-Item -ItemType Directory -Path $apiDirectory -Force | Out-Null

    dotnet publish $hostProject --configuration Release --output $root
    if ($LASTEXITCODE -ne 0) { throw "Publishing the Windows API service host failed." }
    dotnet build $stubProject --configuration Release --output $runtime
    if ($LASTEXITCODE -ne 0) { throw "Building the SCM smoke child process failed." }

    $stubExe = Join-Path $runtime "WindowsApiStub.exe"
    if (-not (Test-Path $stubExe)) { throw "The smoke child executable was not produced." }
    Copy-Item -LiteralPath $stubExe -Destination (Join-Path $runtime "node.exe") -Force
    Set-Content -LiteralPath $apiEntry -Value "// SCM smoke payload" -Encoding ascii
    if (-not (Test-Path $hostExe)) { throw "The published service-host executable is missing its expected layout." }

    & sc.exe query $serviceName 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "A service named $serviceName already exists; refusing to overwrite it." }

    Invoke-Sc @("create", $serviceName, ("binPath= " + '"' + $hostExe + '"'), "start= demand")
    $serviceCreated = $true
    Invoke-Sc @("config", $serviceName, "obj= NT SERVICE\EnterpriseITApi", 'password= ""')
    Invoke-Sc @("sidtype", $serviceName, "unrestricted")

    & icacls.exe $root /grant "NT SERVICE\EnterpriseITApi:(OI)(CI)(RX)" /T /C | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Could not grant temporary service read/execute access to the smoke payload." }

    $sidConfiguration = (& sc.exe qsidtype $serviceName 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $sidConfiguration -notmatch "UNRESTRICTED") {
        throw "SCM did not report the API service SID as UNRESTRICTED."
    }

    Start-Service -Name $serviceName
    $deadline = [DateTime]::UtcNow.AddSeconds(35)
    do {
        $state = (Get-Service -Name $serviceName).Status
        if ($state -eq "Running") { break }
        if ($state -eq "Stopped") { throw "The API service stopped before reaching Running." }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    if ((Get-Service -Name $serviceName).Status -ne "Running") { throw "API service did not reach Running." }

    $childDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $children = Get-ApiChild
        if ($children.Count -eq 1) { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $childDeadline)
    if ($children.Count -ne 1) { throw "Expected exactly one API child after SCM startup; found $($children.Count)." }

    Stop-Service -Name $serviceName
    $stopDeadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if ((Get-Service -Name $serviceName).Status -eq "Stopped") { break }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $stopDeadline)
    if ((Get-Service -Name $serviceName).Status -ne "Stopped") { throw "API service did not stop within the deadline." }

    $childDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $children = Get-ApiChild
        if ($children.Count -eq 0) { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $childDeadline)
    if ($children.Count -ne 0) { throw "API child remained after SCM reported Stopped." }

    Set-Content -LiteralPath $apiEntry -Value "NO_READY" -Encoding ascii
    $startFailedAsExpected = $false
    try { Start-Service -Name $serviceName -ErrorAction Stop }
    catch { $startFailedAsExpected = $true }

    $failureDeadline = [DateTime]::UtcNow.AddSeconds(35)
    do {
        if ((Get-Service -Name $serviceName).Status -eq "Stopped") { break }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $failureDeadline)
    if (-not $startFailedAsExpected -or (Get-Service -Name $serviceName).Status -ne "Stopped") {
        throw "API service did not fail startup cleanly when readiness was unavailable."
    }
    if ((Get-ApiChild).Count -ne 0) { throw "A child process was orphaned after readiness startup timed out." }

    Write-Host "Windows SCM smoke passed: service SID, child SID, readiness, graceful stop/reap and failed-start cleanup."
}
finally {
    if ($serviceCreated) {
        try {
            $state = (Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status
            if ($state -and $state -ne "Stopped") {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        } catch {}
        & sc.exe delete $serviceName | Out-Null
    }
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
