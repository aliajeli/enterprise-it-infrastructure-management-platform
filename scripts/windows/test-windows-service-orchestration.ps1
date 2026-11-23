$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "orchestrate-windows-services.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -ApiDatabaseUrl (ConvertTo-SecureString "unused" -AsPlainText -Force) -WorkerDatabaseUrl (ConvertTo-SecureString "unused" -AsPlainText -Force) -EdgeBindAddress "192.0.2.10" -EdgeHttpsPort 443 -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40)
$p=Get-WindowsServiceOrchestrationPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -EdgeBindAddress "192.0.2.10" -EdgeHttpsPort 443 -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40) -DataRoot (Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")
$expected=@("EnterpriseITPostgreSQL","EnterpriseITApi","EnterpriseITWorker","EnterpriseITWeb","EnterpriseITEdge")
if(($p.StartOrder -join ",") -ne ($expected -join ",")){throw "Five-service start order is incorrect."}
if($p.Dependencies.Count -ne 4 -or $p.ChangesFirewall -or $p.ChangesRouter -or $p.PortMapping){throw "Unsafe service orchestration policy."}
$bad=$false;try{Get-WindowsServiceOrchestrationPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -EdgeBindAddress "127.0.0.1" -EdgeHttpsPort 443 -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40) -DataRoot (Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")|Out-Null}catch{$bad=$true}
if(-not $bad){throw "Loopback Edge bind must be rejected."}

# Validate the complete payload and PostgreSQL policy before any service provisioning.
$preflightRoot=Join-Path $env:TEMP ("enterpriseit-orchestration-preflight-"+[guid]::NewGuid().ToString("N"))
$preflightData=Join-Path $preflightRoot "data"
$preflightProgramData=Join-Path $preflightRoot "programdata"
New-Item -ItemType Directory -Path $preflightRoot,$preflightData,$preflightProgramData -Force|Out-Null
try{
 $fixturePlan=[pscustomobject]@{InstallRoot=(Join-Path $preflightRoot "install");DataRoot=$preflightData;ProgramDataRoot=$preflightProgramData}
 New-Item -ItemType Directory -Path $fixturePlan.InstallRoot -Force|Out-Null
 foreach($file in (Get-WindowsServiceOrchestrationRequiredFiles -Plan $fixturePlan)){
  $parent=Split-Path -Parent $file
  New-Item -ItemType Directory -Path $parent -Force|Out-Null
  $content="fixture"
  if($file -like "*\PG_VERSION"){$content="18"}
  elseif($file -like "*\postgresql.conf"){$content=@("listen_addresses = '127.0.0.1'","port = 5432") -join [Environment]::NewLine}
  elseif($file -like "*\pg_hba.conf"){$content=@("host all all 127.0.0.1/32 scram-sha-256","host all all 0.0.0.0/0 reject","host all all ::/0 reject") -join [Environment]::NewLine}
  [IO.File]::WriteAllText($file,$content)
 }
 $payloadCheck=Test-WindowsServiceOrchestrationPayload -Plan $fixturePlan
 if(-not $payloadCheck.valid -or $payloadCheck.requiredFileCount -ne 15){throw "Complete service payload and PostgreSQL fixture should pass orchestration preflight."}
 $keyringLock=Join-Path $fixturePlan.ProgramDataRoot "EnterpriseIT\CredentialVault\keyring.lock"
 Remove-Item -LiteralPath $keyringLock -Force
 $missingKeyringRejected=$false
 try{Test-WindowsServiceOrchestrationPayload -Plan $fixturePlan|Out-Null}catch{$missingKeyringRejected=$true}
 if(-not $missingKeyringRejected){throw "Missing Credential Vault lock file must fail before service provisioning."}
 [IO.File]::WriteAllText($keyringLock,"")
 $edgeHost=Join-Path $fixturePlan.InstallRoot "EnterpriseIT.EdgeServiceHost.exe"
 Remove-Item -LiteralPath $edgeHost -Force
 $missingRejected=$false
 try{Test-WindowsServiceOrchestrationPayload -Plan $fixturePlan|Out-Null}catch{$missingRejected=$true}
 if(-not $missingRejected){throw "Missing Edge service host must fail before provisioning begins."}
 [IO.File]::WriteAllText($edgeHost,"fixture")
 [IO.File]::WriteAllText((Join-Path $preflightData "pg_hba.conf"),"host all all 127.0.0.1/32 trust")
 $unsafeDatabaseRejected=$false
 try{Test-WindowsServiceOrchestrationPayload -Plan $fixturePlan|Out-Null}catch{$unsafeDatabaseRejected=$true}
 if(-not $unsafeDatabaseRejected){throw "A PostgreSQL authentication policy without remote-address rejection must fail preflight."}
}finally{
 if(Test-Path -LiteralPath $preflightRoot){Remove-Item -LiteralPath $preflightRoot -Recurse -Force -ErrorAction SilentlyContinue}
}

# Rollback must stop only services started by this invocation, in reverse order.
$script:rollbackStops=[System.Collections.Generic.List[string]]::new()
function Stop-Service {
 param([string]$Name,[switch]$Force,[string]$ErrorAction)
 $script:rollbackStops.Add($Name)
 if($Name -eq "EnterpriseITWorker"){throw "synthetic stop failure"}
}
$startedByTest=[System.Collections.Generic.List[string]]::new()
foreach($name in @("EnterpriseITPostgreSQL","EnterpriseITApi","EnterpriseITWorker")){$startedByTest.Add($name)}
Stop-OrchestrationStartedServices -Started $startedByTest
$expectedRollback=@("EnterpriseITWorker","EnterpriseITApi","EnterpriseITPostgreSQL")
if(($script:rollbackStops -join ",") -ne ($expectedRollback -join ",")){throw "Rollback must attempt only newly started services in reverse order, even if one stop fails."}
if($script:rollbackStops -contains "EnterpriseITWeb" -or $script:rollbackStops -contains "EnterpriseITEdge"){throw "Rollback attempted to stop a service that was not started by this invocation."}
Remove-Item Function:\Stop-Service -ErrorAction SilentlyContinue

Write-Host "Five-service orchestration and rollback policy tests passed."
