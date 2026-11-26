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
 if(-not $payloadCheck.valid -or $payloadCheck.requiredFileCount -ne 18){throw "Complete service payload and PostgreSQL fixture should pass orchestration preflight."}

 # SCM service SIDs contain exactly five unsigned subauthorities after S-1-5-80.
 # WhatIf must validate them without executing the placeholder helper.
 $sid="S-1-5-80-1-2-3-4-5"
 foreach($verify in @($false,$true)){
  $dry=Invoke-CredentialVaultProvisioner -Plan $fixturePlan -ServiceSid $sid -VerifyOnly:$verify -WhatIf
  if($dry.status -ne "whatif" -or -not $dry.serviceSidValidated){throw "Valid service SID must be accepted in Vault WhatIf."}
 }
 foreach($invalidSid in @("S-1-5-80-1-2-3-4", "S-1-5-80-1-2-3-4-5-6", "S-1-5-80-4294967296-2-3-4-5", "S-1-5-21-1-2-3-4")){
  $rejected=$false
  try{Invoke-CredentialVaultProvisioner -Plan $fixturePlan -ServiceSid $invalidSid -WhatIf|Out-Null}catch{$rejected=$true}
  if(-not $rejected){throw "Invalid synthetic service SID $invalidSid must be rejected before launching the helper."}
 }

 # ProgramData itself is part of the trusted path and must not be a junction.
 $programDataJunctionTarget=Join-Path $preflightRoot "programdata-junction-target"
 Copy-Item -LiteralPath $preflightProgramData -Destination $programDataJunctionTarget -Recurse
 Remove-Item -LiteralPath $preflightProgramData -Recurse -Force
 $programDataJunctionOutput=& cmd.exe /c "mklink /J `"$preflightProgramData`" `"$programDataJunctionTarget`""
 if($LASTEXITCODE -ne 0){throw "Could not create the ProgramData junction fixture: $programDataJunctionOutput"}
 $programDataJunctionRejected=$false
 try{Test-WindowsServiceOrchestrationPayload -Plan $fixturePlan|Out-Null}catch{$programDataJunctionRejected=$true}
 if(-not $programDataJunctionRejected){throw "ProgramData root junction must be rejected during preflight."}
 Remove-Item -LiteralPath $preflightProgramData -Force
 Rename-Item -LiteralPath $programDataJunctionTarget -NewName "programdata"

 # Fresh install: missing Vault leaf is allowed at payload preflight; the elevated
 # provisioner creates/validates it after API SID provisioning and before API start.
 $keyringLock=Join-Path $fixturePlan.ProgramDataRoot "EnterpriseIT\CredentialVault\keyring.lock"
 $vaultRoot=Split-Path -Parent $keyringLock
 if(Test-Path -LiteralPath $vaultRoot){Remove-Item -LiteralPath $vaultRoot -Recurse -Force}
 $freshInstallPreflight=Test-WindowsServiceOrchestrationPayload -Plan $fixturePlan
 if(-not $freshInstallPreflight.valid){throw "Fresh install payload preflight must not require a pre-existing Credential Vault leaf."}

 # Second capability gate: opens only on a complete plan shape, secure URL
 # inputs, the staged ownership-capability scripts and the full payload
 # preflight (which requires the ownership-verification executable and the
 # initialized cluster pins). Every rejection must happen before DNS or any
 # service change.
 $gateUrls=ConvertTo-SecureString "unused" -AsPlainText -Force
 $gatePlan=[pscustomobject]@{
  InstallRoot=$fixturePlan.InstallRoot;DataRoot=$fixturePlan.DataRoot
  ProgramDataRoot=$fixturePlan.ProgramDataRoot
  EdgeBindAddress="192.0.2.10";EdgeHttpsPort=443
  EdgeTlsHostname="it.example.internal";EdgeCertificateThumbprint=("A"*40)
 }
 $gateAccepted=$true
 try{Assert-WindowsServiceOrchestrationCapability -Plan $gatePlan -ApiDatabaseUrl $gateUrls -WorkerDatabaseUrl $gateUrls|Out-Null}catch{$gateAccepted=$false}
 if(-not $gateAccepted){throw "Capability gate must accept the complete fixture payload."}
 $nullUrlRejected=$false
 try{Assert-WindowsServiceOrchestrationCapability -Plan $gatePlan -ApiDatabaseUrl $null -WorkerDatabaseUrl $gateUrls|Out-Null}catch{$nullUrlRejected=$_.Exception.Message -like '*Separate SecureString API and Worker database URLs*'}
 if(-not $nullUrlRejected){throw "Capability gate must reject a missing database URL before preflight."}
 $incompletePlanRejected=$false
 try{Assert-WindowsServiceOrchestrationCapability -Plan ([pscustomobject]@{}) -ApiDatabaseUrl $gateUrls -WorkerDatabaseUrl $gateUrls|Out-Null}catch{$incompletePlanRejected=$_.Exception.Message -like '*Orchestration plan is incomplete*no services were changed*'}
 if(-not $incompletePlanRejected){throw "Capability gate must reject an incomplete plan before preflight."}
 $emptyScriptRoot=Join-Path $env:TEMP ("enterpriseit-gate-scripts-"+[guid]::NewGuid().ToString("N"))
 New-Item -ItemType Directory -Path $emptyScriptRoot|Out-Null
 try{
  $missingScriptRejected=$false
  try{Assert-WindowsServiceOrchestrationCapability -Plan $gatePlan -ApiDatabaseUrl $gateUrls -WorkerDatabaseUrl $gateUrls -CapabilityScriptRoot $emptyScriptRoot|Out-Null}catch{$missingScriptRejected=$_.Exception.Message -like '*capability script*missing*no services were changed*'}
  if(-not $missingScriptRejected){throw "Capability gate must reject a payload without the ownership-capability scripts."}
 }finally{
  if(Test-Path -LiteralPath $emptyScriptRoot){Remove-Item -LiteralPath $emptyScriptRoot -Recurse -Force -ErrorAction SilentlyContinue}
 }
 $postgresExe=Join-Path $gatePlan.InstallRoot "postgresql\pgsql\bin\postgres.exe"
 Remove-Item -LiteralPath $postgresExe -Force
 $missingFileRejected=$false
 try{Assert-WindowsServiceOrchestrationCapability -Plan $gatePlan -ApiDatabaseUrl $gateUrls -WorkerDatabaseUrl $gateUrls|Out-Null}catch{$missingFileRejected=$_.Exception.Message -like '*Orchestration preflight failed before service provisioning*missing*'}
 if(-not $missingFileRejected){throw "Capability gate must reject a payload with a missing required file."}
 [IO.File]::WriteAllText($postgresExe,"fixture")

 # Recreate vault for reparse tests. A directory junction at the Vault boundary must be
 # rejected before any service mutation.
 New-Item -ItemType Directory -Path $vaultRoot -Force|Out-Null
 [IO.File]::WriteAllText($keyringLock,"")
 $junctionTarget=Join-Path $preflightRoot "junction-target"
 New-Item -ItemType Directory -Path $junctionTarget -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $junctionTarget "keyring.lock"),"")
 Remove-Item -LiteralPath $keyringLock -Force -ErrorAction Stop
 Remove-Item -LiteralPath $vaultRoot -Force -ErrorAction Stop
 $junctionOutput=& cmd.exe /c "mklink /J `"$vaultRoot`" `"$junctionTarget`""
 if($LASTEXITCODE -ne 0){throw "Could not create the local junction fixture required for the reparse-point security test: $junctionOutput"}
 $junctionRejected=$false
 try{Test-WindowsServiceOrchestrationPayload -Plan $fixturePlan|Out-Null}catch{$junctionRejected=$true}
 if(-not $junctionRejected){throw "Credential Vault directory junction must be rejected during preflight."}
 Remove-Item -LiteralPath $vaultRoot -Force -ErrorAction Stop
 New-Item -ItemType Directory -Path $vaultRoot -Force|Out-Null
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
