[CmdletBinding()]
param([string]$BuildOutput=(Join-Path $PSScriptRoot "..\..\apps\api\windows\postgresql-bootstrap\bin\Release\net10.0-windows"))
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (-not $IsWindows -or $env:GITHUB_ACTIONS -ne "true") { throw "Hosted Windows CI only." }
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
  if (-not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Elevated runner required." }
} finally { $id.Dispose() }
$serviceName = "EnterpriseITPostgreSQLBootstrap"
$serviceStartedAt = Get-Date
$serviceAccount = "NT AUTHORITY\LocalService"
$pipeName = "EnterpriseIT.PostgreSQL.Bootstrap.v1"
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) { throw "Refusing to adopt an existing service." }
$build = [IO.Path]::GetFullPath($BuildOutput)
if (-not (Test-Path -LiteralPath (Join-Path $build "EnterpriseIT.PostgreSQLBootstrap.exe") -PathType Leaf)) { throw "Build output missing." }
$version = "0.0." + [guid]::NewGuid().ToString("N").Substring(0,9)
$root = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) "EnterpriseIT\$version"
$userName = "eip" + [guid]::NewGuid().ToString("N").Substring(0,12)
$random = [byte[]]::new(36)
[Security.Cryptography.RandomNumberGenerator]::Fill($random)
$plain = [Convert]::ToBase64String($random) + "Aa1!"
[Array]::Clear($random,0,$random.Length)
$secure = ConvertTo-SecureString $plain -AsPlainText -Force
$plain = $null
$createdRoot = $false; $createdUser = $false; $createdService = $false; $child = $null; $remaining = $null
try {
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  $createdRoot = $true
  Get-ChildItem -LiteralPath $build -Force | Copy-Item -Destination $root -Recurse -Force
  New-LocalUser -Name $userName -Password $secure -AccountExpires ([DateTime]::Now.AddHours(1)) -Description "Disposable bootstrap pipe ACL fixture" | Out-Null
  $createdUser = $true
  $credential = [PSCredential]::new("$env:COMPUTERNAME\$userName",$secure)
  $exe = Join-Path $root "EnterpriseIT.PostgreSQLBootstrap.exe"
  & sc.exe create $serviceName "binPath=" ('"' + $exe + '"') "obj=" $serviceAccount "start=" "demand" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "SCM create failed." }
  $createdService = $true
  & sc.exe sidtype $serviceName unrestricted | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Service SID configuration failed." }
  $serviceConfig = (& sc.exe qc $serviceName 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0 -or $serviceConfig -notlike "*NT AUTHORITY\LocalService*") { throw "Hosted SCM fixture is not running as LocalService." }
  $sid = (& sc.exe qsidtype $serviceName 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0 -or $sid -notmatch "UNRESTRICTED") { throw "Service SID is not unrestricted." }
  & sc.exe start $serviceName | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "SCM start failed." }
  $until = [DateTime]::UtcNow.AddSeconds(20); $state = "Stopped"
  do { Start-Sleep -Milliseconds 250; $state = (Get-Service $serviceName).Status } while ($state -ne "Running" -and [DateTime]::UtcNow -lt $until)
  if ($state -ne "Running") { throw "Service did not remain running under its configured SCM identity." }

  # Hosted runners reject custom NT SERVICE logon accounts (SCM 1057). LocalService plus the unrestricted per-service SID exercises the same service-SID authorization and pipe ACL; production virtual-account assignment remains a Windows Server acceptance gate.
  # Authorized administrator positive control; deliberately malformed frame, no secret.
  $adminPipe = [IO.Pipes.NamedPipeClientStream]::new(".",$pipeName,[IO.Pipes.PipeDirection]::InOut)
  try {
    try {
      $adminPipe.Connect(15000)
    } catch {
      $currentState = (Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status
      $query = (& sc.exe queryex $serviceName 2>&1 | Out-String)
      Write-Host ("Bootstrap SCM state: " + $currentState)
      Write-Host $query
      foreach ($logName in @("Application","System")) {
        try {
          $events = @(Get-WinEvent -FilterHashtable @{LogName=$logName;StartTime=$serviceStartedAt} -MaxEvents 8 -ErrorAction Stop)
          foreach ($event in $events) {
            $message = (($event.Message -replace "[\r\n]+"," ").Trim())
            if ($message.Length -gt 1000) { $message = $message.Substring(0,1000) }
            Write-Host ("EVENT {0} ID={1} SOURCE={2} MESSAGE={3}" -f $logName,$event.Id,$event.ProviderName,$message)
          }
        } catch { Write-Host ("No readable " + $logName + " events for the fixture window.") }
      }
      throw "Bootstrap named pipe did not become available; inspect bounded SCM/event diagnostics above."
    }
    $adminPipe.ReadTimeout = 5000
    $adminPipe.Write([byte[]](0,0,0,0),0,4); $adminPipe.Flush()
    $response = [byte[]]::new(1)
    if ($adminPipe.Read($response,0,1) -ne 1 -or $response[0] -ne 1) { throw "Admin pipe positive control failed." }
  } finally { $adminPipe.Dispose() }

  $probe = @'
$name = "EnterpriseIT.PostgreSQL.Bootstrap.v1"
$until = [DateTime]::UtcNow.AddSeconds(15)
while ([DateTime]::UtcNow -lt $until) {
  $p = [IO.Pipes.NamedPipeClientStream]::new(".",$name,[IO.Pipes.PipeDirection]::InOut)
  try { $p.Connect(500); exit 41 }
  catch [UnauthorizedAccessException] { exit 0 }
  catch [IO.IOException] { $code = $_.Exception.HResult -band 0xFFFF; if ($code -eq 5) { exit 0 }; Start-Sleep -Milliseconds 200 }
  catch [TimeoutException] { Start-Sleep -Milliseconds 200 }
  finally { $p.Dispose() }
}
exit 42
'@
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))
  $child = Start-Process -FilePath (Join-Path $PSHOME "pwsh.exe") -Credential $credential -PassThru -ArgumentList @("-NoLogo","-NoProfile","-NonInteractive","-EncodedCommand",$encoded)
  if (-not $child.WaitForExit(20000)) { $child.Kill(); throw "Standard User probe timed out." }
  if ($child.ExitCode -ne 0) {
    if ($child.ExitCode -eq 41) { throw "Standard User connected to the administrator-only pipe." }
    throw "Standard User pipe denial was not established."
  }
  if ((Get-Service $serviceName).Status -ne "Running") { throw "Service stopped after access test." }
  Write-Host "SCM startup and same-session Standard User pipe denial passed; no initdb or credential was used."
} finally {
  if ($null -ne $child) { try { if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit(10000) | Out-Null } } catch {}; $child.Dispose() }
  if ($createdService) {
    try { $s = Get-Service $serviceName -ErrorAction SilentlyContinue; if ($null -ne $s -and $s.Status -eq "Running") { & sc.exe stop $serviceName | Out-Null; Start-Sleep -Seconds 2 } } catch {}
    & sc.exe delete $serviceName | Out-Null
    $until = [DateTime]::UtcNow.AddSeconds(10)
    do { Start-Sleep -Milliseconds 200; $remaining = Get-Service $serviceName -ErrorAction SilentlyContinue } while ($null -ne $remaining -and [DateTime]::UtcNow -lt $until)
  }
  if ($createdUser) { try { $u = Get-LocalUser $userName -ErrorAction Stop; Remove-LocalUser -SID $u.SID -ErrorAction Stop } catch {} }
  $secure.Dispose()
  if ($createdRoot -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
  if ($null -ne $remaining) { throw "Service cleanup could not be confirmed." }
  if ($createdUser -and (Get-LocalUser $userName -ErrorAction SilentlyContinue)) { throw "Test-account cleanup could not be confirmed." }
}
