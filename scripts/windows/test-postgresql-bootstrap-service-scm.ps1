[CmdletBinding()]
param(
  [string]$BuildOutput=(Join-Path $PSScriptRoot "..\..\apps\api\windows\postgresql-bootstrap\bin\Release\net10.0-windows"),
  [ValidateSet("NT AUTHORITY\LocalService","NT SERVICE\EnterpriseITPostgreSQLBootstrap")]
  [string]$ServiceAccount="NT AUTHORITY\LocalService"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (-not $IsWindows) { throw "Windows-only acceptance test." }
if ($env:GITHUB_ACTIONS -eq "true" -and $ServiceAccount -ne "NT AUTHORITY\LocalService") { throw "Hosted CI must use LocalService; run the virtual-account acceptance on a supported Windows Server." }
if ($ServiceAccount -eq "NT SERVICE\EnterpriseITPostgreSQLBootstrap" -and (Get-CimInstance Win32_OperatingSystem).ProductType -eq 1) { throw "The dedicated virtual-account acceptance requires Windows Server, not a client Windows SKU." }
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
  if (-not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Elevated runner required." }
} finally { $id.Dispose() }
$serviceName = "EnterpriseITPostgreSQLBootstrap"
$serviceStartedAt = Get-Date
$serviceAccount = $ServiceAccount
$pipeName = "EnterpriseIT.PostgreSQL.Bootstrap.v2"
$diagnosticRoot = Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18"
$diagnosticFile = Join-Path $diagnosticRoot "bootstrap-smoke.log"
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) { throw "Refusing to adopt an existing service." }
$build = [IO.Path]::GetFullPath($BuildOutput)
if (-not (Test-Path -LiteralPath (Join-Path $build "EnterpriseIT.PostgreSQLBootstrap.exe") -PathType Leaf)) { throw "Build output missing." }
$version = "0.0." + [Security.Cryptography.RandomNumberGenerator]::GetInt32(100000000,999999999).ToString([Globalization.CultureInfo]::InvariantCulture)
$root = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) "EnterpriseIT\$version"
$userName = "eip" + [guid]::NewGuid().ToString("N").Substring(0,12)
$random = [byte[]]::new(36)
[Security.Cryptography.RandomNumberGenerator]::Fill($random)
$plain = [Convert]::ToBase64String($random) + "Aa1!"
[Array]::Clear($random,0,$random.Length)
$secure = ConvertTo-SecureString $plain -AsPlainText -Force
$plain = $null
$createdRoot = $false; $createdUser = $false; $createdService = $false; $createdDiagnosticRoot = $false; $createdPgDownloadRoot = $false; $child = $null; $remaining = $null; $bootstrapSecure = $null; $bootstrapPtr = [IntPtr]::Zero; $bootstrapChars = $null; $bootstrapBytes = $null; $bootstrapFrame = $null; $initdbPipe = $null; $testStage = "fixture-setup"
try {
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  $createdRoot = $true
  Get-ChildItem -LiteralPath $build -Force | Copy-Item -Destination $root -Recurse -Force

  # Stage the real, checksum-verified PostgreSQL 18.7 payload beneath the
  # versioned service root so the service itself launches initdb.
  $tempBase = if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { $env:RUNNER_TEMP } else { $env:TEMP }
  if ([string]::IsNullOrWhiteSpace($tempBase)) { throw "A temporary directory is required for the acceptance fixture." }
  $pgDownloadRoot = Join-Path $tempBase ("enterpriseit-bootstrap-pg-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $pgDownloadRoot -Force | Out-Null
  $createdPgDownloadRoot = $true
  $pgArchive = Join-Path $pgDownloadRoot "postgresql-18.7-1-windows-x64-binaries.zip"
  $pgChecksum = $pgArchive + ".sha256"
  $pgExtract = Join-Path $pgDownloadRoot "extract"
  $pgUrl = "https://get.enterprisedb.com/postgresql/postgresql-18.7-1-windows-x64-binaries.zip"
  Invoke-WebRequest -Uri $pgUrl -OutFile $pgArchive -UseBasicParsing
  Invoke-WebRequest -Uri ($pgUrl + ".sha256") -OutFile $pgChecksum -UseBasicParsing
  $pgExpected = [regex]::Match((Get-Content -LiteralPath $pgChecksum -Raw),"(?i)\b[a-f0-9]{64}\b").Value
  if ($pgExpected.Length -ne 64 -or (Get-FileHash -LiteralPath $pgArchive -Algorithm SHA256).Hash -ine $pgExpected) { throw "PostgreSQL 18.7 fixture archive checksum mismatch." }
  Expand-Archive -LiteralPath $pgArchive -DestinationPath $pgExtract
  $pgInitDbFiles = @(Get-ChildItem -LiteralPath $pgExtract -Filter "initdb.exe" -File -Recurse)
  if ($pgInitDbFiles.Count -ne 1) { throw "Expected exactly one initdb.exe in the PostgreSQL fixture archive." }
  $pgBinRoot = Split-Path -Parent $pgInitDbFiles[0].FullName
  if ((Split-Path -Leaf $pgBinRoot) -ne "bin") { throw "PostgreSQL fixture initdb is not beneath a bin directory." }
  $pgRoot = Split-Path -Parent $pgBinRoot
  if ((Split-Path -Leaf $pgRoot) -ne "pgsql") { throw "Unexpected PostgreSQL fixture payload layout." }
  $pgDestination = Join-Path $root "postgresql\pgsql"
  New-Item -ItemType Directory -Path $pgDestination -Force | Out-Null
  Copy-Item -Path (Join-Path $pgRoot "*") -Destination $pgDestination -Recurse -Force
  if (-not (Test-Path -LiteralPath (Join-Path $pgDestination "bin\initdb.exe") -PathType Leaf)) { throw "Staged PostgreSQL initdb payload is incomplete." }

  New-LocalUser -Name $userName -Password $secure -AccountExpires ([DateTime]::Now.AddHours(1)) -Description "Disposable bootstrap pipe ACL fixture" | Out-Null
  $createdUser = $true
  $credential = [PSCredential]::new("$env:COMPUTERNAME\$userName",$secure)
  $exe = Join-Path $root "EnterpriseIT.PostgreSQLBootstrap.exe"
  & sc.exe create $serviceName "binPath=" ('"' + $exe + '" --smoke-diagnostics') "obj=" $serviceAccount "start=" "demand" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "SCM create failed." }
  $createdService = $true
  & sc.exe sidtype $serviceName unrestricted | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Service SID configuration failed." }
  $serviceConfig = (& sc.exe qc $serviceName 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0 -or $serviceConfig -notlike ("*" + $serviceAccount + "*")) { throw "SCM service account does not match the requested acceptance identity." }
  $sid = (& sc.exe qsidtype $serviceName 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0 -or $sid -notmatch "UNRESTRICTED") { throw "Service SID is not unrestricted." }
  if (Test-Path -LiteralPath $diagnosticRoot) { throw "Bootstrap diagnostic directory already exists; refusing to reuse it." }
  New-Item -ItemType Directory -Path $diagnosticRoot -Force | Out-Null
  $createdDiagnosticRoot = $true
  $sidOutput = (& sc.exe showsid $serviceName 2>&1 | Out-String)
  $sidMatch = [regex]::Match($sidOutput,"S-1-5-80-(?:\d+-){4}\d+")
  if (-not $sidMatch.Success) { throw "SCM did not return a valid service SID for diagnostic ACL." }
  $serviceSid = $sidMatch.Value
  Write-Host ("SCM service SID: " + $serviceSid)
  & icacls.exe $diagnosticRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*" + $serviceSid + ":(OI)(CI)(M)") | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Could not protect bootstrap diagnostic directory." }
  # The service pins the fixed ProgramData chain with NtCreateFile FILE_OPEN
  # and deliberately refuses to create the data leaf; the privileged
  # provisioner (and this fixture on its behalf) must create it first with the
  # provisioner's leaf ACL: SYSTEM/Administrators full, bootstrap service SID
  # Modify. initdb runs as the service identity and needs Modify to populate
  # an otherwise empty cluster directory.
  $dataRoot = Join-Path $diagnosticRoot "data"
  if (Test-Path -LiteralPath $dataRoot) { throw "Bootstrap data leaf already exists; refusing to reuse it." }
  New-Item -ItemType Directory -Path $dataRoot | Out-Null
  & icacls.exe $dataRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*" + $serviceSid + ":(OI)(CI)(M)") | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Could not protect bootstrap data leaf." }
  # This marker activates a bounded 15-second initdb hold only in this
  # disposable smoke fixture, allowing a separate Standard User to probe
  # PROCESS_DUP_HANDLE on the real initdb parent and restricted re-exec child.
  New-Item -ItemType File -Path (Join-Path $diagnosticRoot "bootstrap-smoke.pause-initdb") -Force | Out-Null
  & sc.exe start $serviceName | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "SCM start failed." }
  $until = [DateTime]::UtcNow.AddSeconds(20); $state = "Stopped"
  do { Start-Sleep -Milliseconds 250; $state = (Get-Service $serviceName).Status } while ($state -ne "Running" -and [DateTime]::UtcNow -lt $until)
  if ($state -eq "Running") {
    $identityTraceDeadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
      $identityTrace = if (Test-Path -LiteralPath $diagnosticFile) { [IO.File]::ReadAllLines($diagnosticFile) } else { @() }
      $primaryIdentityMatch = $identityTrace -contains "service-sid-primary-identity-match:True"
      $enabledGroupMatch = $identityTrace -contains "service-sid-enabled:True"
      if (($primaryIdentityMatch -or $enabledGroupMatch) -and $identityTrace -contains "service-sid-deny-only:False") { break }
      Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $identityTraceDeadline)
    $primaryIdentityMatch = $identityTrace -contains "service-sid-primary-identity-match:True"
    $enabledGroupMatch = $identityTrace -contains "service-sid-enabled:True"
    if ((-not $primaryIdentityMatch -and -not $enabledGroupMatch) -or $identityTrace -notcontains "service-sid-deny-only:False") {
      throw "SCM service token did not prove a primary service identity or an enabled, non-deny-only service SID."
    }
    Write-Host "Service token attributes passed: service SID is the primary identity or an enabled group, and is not deny-only."
  }
  if ($state -ne "Running") {
    $query = (& sc.exe queryex $serviceName 2>&1 | Out-String)
    Write-Host ("Bootstrap SCM state: " + $state)
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
    if (Test-Path -LiteralPath $diagnosticFile) {
      Get-Content -LiteralPath $diagnosticFile | ForEach-Object { Write-Host ("TRACE: " + $_) }
    } else { Write-Host "No bootstrap trace file was created." }
    throw "Service did not remain running under its configured SCM identity; inspect bounded event diagnostics above."
  }

  # CI uses LocalService because hosted runners reject custom virtual-account logon (SCM 1057). On Windows Server, pass -ServiceAccount "NT SERVICE\\EnterpriseITPostgreSQLBootstrap" to exercise the actual production identity.
  # Authorized administrator positive control; deliberately malformed frame, no secret.
  $testStage = "admin-pipe-connect"
  $adminPipe = [IO.Pipes.NamedPipeClientStream]::new(".",$pipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::None,[Security.Principal.TokenImpersonationLevel]::Impersonation)
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
    if (Test-Path -LiteralPath $diagnosticFile) {
      Get-Content -LiteralPath $diagnosticFile | ForEach-Object { Write-Host ("TRACE: " + $_) }
    } else { Write-Host "No bootstrap trace file was created." }
      throw "Bootstrap named pipe did not become available; inspect bounded SCM/event diagnostics above."
    }
    $testStage = "admin-preflight-read"
    $preflight = [byte[]]::new(1)
    $preflightTask = $adminPipe.ReadAsync($preflight,0,1)
    $preflightCount = $preflightTask.WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
    if ($preflightCount -ne 1 -or $preflight[0] -ne 0) { throw "Administrator token was rejected before request framing." }
    $testStage = "admin-malformed-frame-write"
    $adminPipe.Write([byte[]](0,0,0,0),0,4); $adminPipe.Flush()
    $testStage = "admin-malformed-frame-response"
    $response = [byte[]]::new(1)
    $readTask = $adminPipe.ReadAsync($response,0,1)
    $readCount = $readTask.WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
    if ($readCount -ne 1 -or $response[0] -ne 1) { throw "Admin pipe malformed-frame rejection control failed." }
  } finally { $adminPipe.Dispose() }

  $testStage = "standard-user-pipe-denial"
  $probe = @'
$name = "EnterpriseIT.PostgreSQL.Bootstrap.v2"
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
  $probeStart = [Diagnostics.ProcessStartInfo]::new()
  $probeStart.FileName = Join-Path $PSHOME "pwsh.exe"
  foreach ($argument in @("-NoLogo","-NoProfile","-NonInteractive","-Command",$probe)) {
    $probeStart.ArgumentList.Add($argument)
  }
  $probeStart.UseShellExecute = $false
  $probeStart.CreateNoWindow = $true
  $probeStart.RedirectStandardInput = $true
  $probeStart.RedirectStandardOutput = $true
  $probeStart.RedirectStandardError = $true
  $probeStart.Domain = $env:COMPUTERNAME
  $probeStart.UserName = $userName
  $probeStart.Password = $secure
  $probeStart.LoadUserProfile = $false
  $child = [Diagnostics.Process]::Start($probeStart)
  if ($null -eq $child) { throw "Standard User probe process could not be created." }
  if (-not $child.WaitForExit(20000)) { $child.Kill($true); throw "Standard User probe timed out." }
  if ($child.ExitCode -ne 0) {
    if ($child.ExitCode -eq 41) { throw "Standard User connected to the administrator-only pipe." }
    throw "Standard User pipe denial was not established."
  }
  if ((Get-Service $serviceName).Status -ne "Running") { throw "Service stopped after access test." }
  $child.Dispose(); $child = $null

  # Send a synthetic credential through the production protocol. The service
  # launches real PostgreSQL 18.7 initdb under the selected SCM identity and
  # its service SID, then holds before stdin transmission so the Standard User can probe
  # both the parent and PostgreSQL's restricted re-exec child.
  $testStage = "credentialed-service-initdb"
  $bootstrapMarker = "ci-bootstrap-" + [guid]::NewGuid().ToString("N") + "-Aa1!"
  $bootstrapSecure = ConvertTo-SecureString $bootstrapMarker -AsPlainText -Force
  $bootstrapPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($bootstrapSecure)
  $bootstrapChars = [char[]]::new($bootstrapSecure.Length)
  [Runtime.InteropServices.Marshal]::Copy($bootstrapPtr,$bootstrapChars,0,$bootstrapChars.Length)
  $bootstrapBytes = [Text.UTF8Encoding]::new($false,$true).GetBytes($bootstrapChars)
  $bootstrapFrame = [byte[]]::new(4 + $bootstrapBytes.Length)
  $lengthPrefix = [BitConverter]::GetBytes([int]$bootstrapBytes.Length)
  [Array]::Reverse($lengthPrefix)
  [Array]::Copy($lengthPrefix,0,$bootstrapFrame,0,4)
  [Array]::Copy($bootstrapBytes,0,$bootstrapFrame,4,$bootstrapBytes.Length)

  $initdbPipe = [IO.Pipes.NamedPipeClientStream]::new(".",$pipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::None,[Security.Principal.TokenImpersonationLevel]::Impersonation)
  $initdbPipe.Connect(15000)
  $initdbPreflight = [byte[]]::new(1)
  $initdbPreflightTask = $initdbPipe.ReadAsync($initdbPreflight,0,1)
  $initdbPreflightCount = $initdbPreflightTask.WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
  if ($initdbPreflightCount -ne 1 -or $initdbPreflight[0] -ne 0) { throw "Administrator was rejected before real initdb credential transmission." }
  $initdbPipe.Write($bootstrapFrame,0,$bootstrapFrame.Length)
  $initdbPipe.Flush()
  $initdbFinal = [byte[]]::new(1)
  $initdbFinalTask = $initdbPipe.ReadAsync($initdbFinal,0,1)

  $testStage = "wait-initdb-process-marker"
  $initdbPid = 0
  $traceDeadline = [DateTime]::UtcNow.AddSeconds(90)
  do {
    if (Test-Path -LiteralPath $diagnosticFile) {
      # Read complete lines so CRLF and LF traces are parsed identically.
      # Raw multiline regex matching can leave a carriage return before LF.
      foreach ($traceLine in [IO.File]::ReadAllLines($diagnosticFile)) {
        $prefix = "initdb-process-started:"
        if ($traceLine.StartsWith($prefix,[StringComparison]::Ordinal)) {
          $candidatePid = 0
          $pidText = $traceLine.Substring($prefix.Length)
          if ([int]::TryParse($pidText,[ref]$candidatePid) -and $candidatePid -gt 0) {
            $initdbPid = $candidatePid
            break
          }
        }
      }
      if ($initdbPid -gt 0) { break }
    }
    Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $traceDeadline)
  if ($initdbPid -le 0) { throw "Service did not publish the non-secret initdb process marker during the smoke hold." }

  $testStage = "wait-initdb-reexec-child"
  $reexecPid = 0
  $reexecDeadline = [DateTime]::UtcNow.AddSeconds(20)
  do {
    $reexecChildren = @(Get-CimInstance -ClassName Win32_Process -Filter ("ParentProcessId = " + $initdbPid) -ErrorAction Stop | Where-Object { $_.Name -ieq "initdb.exe" })
    if ($reexecChildren.Count -gt 1) { throw "Ambiguous PostgreSQL initdb re-exec child." }
    if ($reexecChildren.Count -eq 1) { $reexecPid = [int]$reexecChildren[0].ProcessId; break }
    Start-Sleep -Milliseconds 150
  } while ([DateTime]::UtcNow -lt $reexecDeadline)
  if ($reexecPid -le 0) { throw "PostgreSQL restricted initdb re-exec child was not observed during the smoke hold." }

  foreach ($targetPid in @($initdbPid,$reexecPid)) {
    $processInfo = @(Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId = " + $targetPid) -ErrorAction Stop)
    if ($processInfo.Count -ne 1 -or [string]$processInfo[0].CommandLine -match [regex]::Escape($bootstrapMarker)) { throw "Synthetic credential appeared in an initdb command line." }
  }

  $testStage = "standard-user-process-handle-denial"
  $handleProbe = @'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class EnterpriseItServiceInitDbAccessProbe {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll")] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool CloseHandle(IntPtr handle);
}
"@
$denied=0
foreach($targetPid in @(__INITDB_PARENT_PID__,__INITDB_REEXEC_PID__)){
 $h=[EnterpriseItServiceInitDbAccessProbe]::OpenProcess(0x40,$false,$targetPid)
 if($h -ne [IntPtr]::Zero){$null=[EnterpriseItServiceInitDbAccessProbe]::CloseHandle($h);exit 41}
 if([Runtime.InteropServices.Marshal]::GetLastWin32Error() -eq 5){$denied++}else{exit 42}
}
if($denied -eq 2){exit 0};exit 43
'@
  $handleProbe = $handleProbe.Replace("__INITDB_PARENT_PID__",[string]$initdbPid).Replace("__INITDB_REEXEC_PID__",[string]$reexecPid)
  $handleProbeStart = [Diagnostics.ProcessStartInfo]::new()
  $handleProbeStart.FileName = Join-Path $PSHOME "pwsh.exe"
  foreach ($argument in @("-NoLogo","-NoProfile","-NonInteractive","-Command",$handleProbe)) { $handleProbeStart.ArgumentList.Add($argument) }
  $handleProbeStart.UseShellExecute = $false
  $handleProbeStart.CreateNoWindow = $true
  $handleProbeStart.RedirectStandardInput = $true
  $handleProbeStart.RedirectStandardOutput = $true
  $handleProbeStart.RedirectStandardError = $true
  $handleProbeStart.Domain = $env:COMPUTERNAME
  $handleProbeStart.UserName = $userName
  $handleProbeStart.Password = $secure
  $handleProbeStart.LoadUserProfile = $false
  $child = [Diagnostics.Process]::Start($handleProbeStart)
  if ($null -eq $child) { throw "Standard User initdb process-access probe could not be created." }
  if (-not $child.WaitForExit(15000)) { $child.Kill($true); throw "Standard User initdb process-access probe timed out." }
  if ($child.ExitCode -ne 0) {
    if ($child.ExitCode -eq 41) { throw "Standard User obtained PROCESS_DUP_HANDLE on a service-owned initdb process." }
    throw "Standard User PROCESS_DUP_HANDLE denial was not established for both initdb processes."
  }
  $child.Dispose(); $child = $null

  $testStage = "wait-initdb-completion"
  $finalCount = $initdbFinalTask.WaitAsync([TimeSpan]::FromMinutes(3.5)).GetAwaiter().GetResult()
  if ($finalCount -ne 1 -or $initdbFinal[0] -ne 0) { throw "Service-owned real PostgreSQL 18.7 initdb did not complete successfully." }
  $dataRoot = Join-Path $diagnosticRoot "data"
  if (-not (Test-Path -LiteralPath (Join-Path $dataRoot "PG_VERSION") -PathType Leaf) -or (Get-Content -LiteralPath (Join-Path $dataRoot "PG_VERSION") -Raw).Trim() -ne "18") { throw "Service-owned initdb did not create a PostgreSQL 18 cluster." }
  if ((Get-Content -LiteralPath (Join-Path $dataRoot "pg_hba.conf") -Raw) -notmatch "scram-sha-256") { throw "Service-owned initdb did not produce SCRAM authentication policy." }

  foreach ($file in @(Get-ChildItem -LiteralPath $diagnosticRoot -File -Recurse)) {
    $diskBytes = [IO.File]::ReadAllBytes($file.FullName)
    try {
      if ([Text.Encoding]::UTF8.GetString($diskBytes).Contains($bootstrapMarker)) { throw "Synthetic credential was found in a ProgramData file." }
    } finally { [Array]::Clear($diskBytes,0,$diskBytes.Length) }
  }
  if ((Get-Service $serviceName).Status -ne "Running") { throw "Service stopped after real initdb operation." }
  Write-Host "SCM, Administrator preflight, Standard User pipe denial, real PostgreSQL 18.7 service-owned initdb, Standard User PROCESS_DUP_HANDLE denial on parent/re-exec child, SCRAM and plaintext-marker scan passed."

} catch {
  Write-Host ("Bootstrap SCM fixture failed at stage: " + $testStage)
  if (Test-Path -LiteralPath $diagnosticFile) {
    Get-Content -LiteralPath $diagnosticFile | ForEach-Object { Write-Host ("TRACE: " + $_) }
  } else { Write-Host "No bootstrap trace file was created before fixture failure." }
  try { Write-Host ((& sc.exe queryex $serviceName 2>&1 | Out-String)) } catch {}
  throw
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
  if ($createdDiagnosticRoot -and (Test-Path -LiteralPath $diagnosticRoot)) { Remove-Item -LiteralPath $diagnosticRoot -Recurse -Force -ErrorAction SilentlyContinue }
  if ($createdRoot -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
  if ($createdPgDownloadRoot -and (Test-Path -LiteralPath $pgDownloadRoot)) { Remove-Item -LiteralPath $pgDownloadRoot -Recurse -Force -ErrorAction SilentlyContinue }
  if ($initdbPipe) { $initdbPipe.Dispose() }
  if ($bootstrapPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bootstrapPtr) }
  if ($bootstrapChars) { [Array]::Clear($bootstrapChars,0,$bootstrapChars.Length) }
  if ($bootstrapBytes) { [Array]::Clear($bootstrapBytes,0,$bootstrapBytes.Length) }
  if ($bootstrapFrame) { [Array]::Clear($bootstrapFrame,0,$bootstrapFrame.Length) }
  if ($bootstrapSecure) { $bootstrapSecure.Dispose() }
  $bootstrapMarker = $null
  if ($null -ne $remaining) { throw "Service cleanup could not be confirmed." }
  if ($createdUser -and (Get-LocalUser $userName -ErrorAction SilentlyContinue)) { throw "Test-account cleanup could not be confirmed." }
}
