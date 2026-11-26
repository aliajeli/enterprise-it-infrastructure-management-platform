$ErrorActionPreference="Stop"
$secret=ConvertTo-SecureString "synthetic-test-secret" -AsPlainText -Force
# DataRoot points at a deterministic missing location: capability execution
# must fail closed on cluster state before any server contact or mutation.
$missingDataRoot=Join-Path $env:TEMP ("enterpriseit-safety-missing-data-"+[guid]::NewGuid().ToString("N"))
if(Test-Path -LiteralPath $missingDataRoot){throw "Safety fixture path unexpectedly exists."}
$bootstrap=@{
 PgHost="127.0.0.1";PgPort=5432;AdminUser="test_admin";AdminPassword=$secret
 DatabaseName="test_db";SchemaOwnerRole="test_owner";MigrationRole="test_migrator";MigrationPassword=$secret
 ApiRole="test_api";ApiPassword=$secret;WorkerRole="test_worker";WorkerPassword=$secret
 DataRoot=$missingDataRoot
}
$migration=@{
 InstallRoot=(Join-Path $env:TEMP "nonexistent-install");PgHost="127.0.0.1";PgPort=5432
 DatabaseName="test_db";MigrationRole="test_migrator";MigrationPassword=$secret
 SchemaOwnerRole="test_owner";ApiRole="test_api";WorkerRole="test_worker";AdminPassword=$secret;AdminUser="test_admin"
}
foreach($case in @(
 @{Script=(Join-Path $PSScriptRoot "bootstrap-postgresql-database.ps1");Arguments=$bootstrap;BlockedPattern='*PostgreSQL cluster is not initialized*refusing database bootstrap*';BlockedLabel="Database bootstrap must fail closed on cluster state before any server contact."},
 @{Script=(Join-Path $PSScriptRoot "invoke-postgresql-migrations.ps1");Arguments=$migration;BlockedPattern='*disabled pending secure credential transport*';BlockedLabel="Migration must remain blocked until its own capability opens."}
)){
 $scriptPath=$case.Script
 $parameters=$case.Arguments
 $preview=& $scriptPath @parameters -WhatIf | ConvertFrom-Json
 if($preview.status -ne "whatif" -or $preview.mutated){throw "Database WhatIf must not mutate."}
 # Reject bad endpoints, reserved/ambiguous identifiers and role collisions
 # during WhatIf as well as execution. Neither path may contact a server.
 $invalidCases=@(
  @{Key='PgHost';Value='localhost'},
  @{Key='PgHost';Value='192.0.2.2'},
  @{Key='PgPort';Value=0},
  @{Key='PgPort';Value=65536},
  @{Key='AdminUser';Value='bad user'},
  @{Key='AdminUser';Value='public'},
  @{Key='DatabaseName';Value='postgres'},
  @{Key='DatabaseName';Value='template1'},
  @{Key='DatabaseName';Value='Bad_Case'},
  @{Key='DatabaseName';Value=('a'*64)},
  @{Key='MigrationRole';Value='pg_reserved'},
  @{Key='MigrationRole';Value='postgres'},
  @{Key='ApiRole';Value='public'},
  @{Key='WorkerRole';Value='test_api'},
  @{Key='MigrationRole';Value='test_owner'},
  @{Key='ApiRole';Value='test_admin'},
  @{Key='SchemaOwnerRole';Value='test_worker'},
  @{Key='ApiRole';Value="test_api;DROP ROLE postgres"}
 )
 foreach($invalid in $invalidCases){
  $bad=$parameters.Clone();$bad[$invalid.Key]=$invalid.Value
  foreach($previewOnly in @($true,$false)){
   $rejected=$false
   try{& $scriptPath @bad -WhatIf:$previewOnly -Confirm:$false | Out-Null}catch{
    if($_.Exception.Message -match 'synthetic-test-secret'){throw 'Validation exposed a secret.'}
    $rejected=$_.Exception.Message -like '*PostgreSQL deployment*' -or $_.Exception.Message -like '*PostgreSQL database name*' -or $_.Exception.Message -like '*PostgreSQL administrator role*'
   }
   if(-not $rejected){throw "Invalid PostgreSQL deployment input was not rejected before the disabled operation."}
  }
 }
 $blocked=$false
 try{& $scriptPath @parameters -Confirm:$false | Out-Null}catch{
  if($_.Exception.Message -match 'synthetic-test-secret'){throw "Database failure exposed a secret."}
  $blocked=$_.Exception.Message -like $case.BlockedPattern
 }
 if(-not $blocked){throw $case.BlockedLabel}
}
if(Test-Path -LiteralPath $missingDataRoot){throw "Fail-closed database bootstrap created its missing data fixture."}
$pf=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
. (Join-Path $PSScriptRoot "orchestrate-windows-services.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -ApiDatabaseUrl $secret -WorkerDatabaseUrl $secret -EdgeBindAddress "192.0.2.10" -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40)
$blocked=$false
try{Invoke-WindowsServiceOrchestration -Plan ([pscustomobject]@{}) -ApiDatabaseUrl $secret -WorkerDatabaseUrl $secret -Bootstrap @{} | Out-Null}catch{
 $blocked=$_.Exception.Message -like '*bootstrap capability prerequisites are not satisfied*no services were changed*'
}
if(-not $blocked){throw "Orchestration must reject an incomplete bootstrap capability before preflight or service mutation."}
# Second capability gate: an incomplete plan must fail closed before DNS,
# payload preflight or any service mutation (the former unconditional
# "disabled pending ownership verification" throw, now testable).
$blocked=$false
try{Invoke-WindowsServiceOrchestration -Plan ([pscustomobject]@{}) -ApiDatabaseUrl $secret -WorkerDatabaseUrl $secret | Out-Null}catch{
 $blocked=$_.Exception.Message -like '*Orchestration plan is incomplete*no services were changed*'
}
if(-not $blocked){throw "Orchestration without bootstrap must fail closed on an incomplete plan before preflight or service mutation."}
# A complete bootstrap input set opens the first capability gate and a
# plan-shaped input opens the second; execution must then stop at payload
# preflight - which requires the ownership-verification executable and the
# initialized cluster pins - before any service mutation.
$fullBootstrap=@{
 AdminUser="test_admin";AdminPassword=$secret;DatabaseName="test_db"
 SchemaOwnerRole="test_owner";MigrationRole="test_migrator";MigrationPassword=$secret
 ApiRuntimeRole="test_api";ApiRuntimePassword=$secret
 WorkerRuntimeRole="test_worker";WorkerRuntimePassword=$secret
}
$ownershipShapedPlan=[pscustomobject]@{
 InstallRoot=(Join-Path $pf "EnterpriseIT\9.9.9")
 DataRoot=(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")
 EdgeBindAddress="192.0.2.10";EdgeHttpsPort=443
 EdgeTlsHostname="it.example.internal";EdgeCertificateThumbprint=("A"*40)
}
$blocked=$false
try{Invoke-WindowsServiceOrchestration -Plan $ownershipShapedPlan -ApiDatabaseUrl $secret -WorkerDatabaseUrl $secret -Bootstrap $fullBootstrap | Out-Null}catch{
 $blocked=$_.Exception.Message -like '*Orchestration preflight failed before service provisioning*missing*'
}
if(-not $blocked){throw "Complete bootstrap inputs must open both capability gates and stop at payload preflight before any service mutation."}
$rejected=$false
$collidingBootstrap=$fullBootstrap.Clone()
$collidingBootstrap["WorkerRuntimeRole"]="test_api"
try{Invoke-WindowsServiceOrchestration -Plan ([pscustomobject]@{}) -ApiDatabaseUrl $secret -WorkerDatabaseUrl $secret -Bootstrap $collidingBootstrap | Out-Null}catch{
 $rejected=$_.Exception.Message -like '*PostgreSQL deployment roles must be distinct*'
}
if(-not $rejected){throw "Bootstrap capability must reject colliding deployment roles before preflight."}
Write-Host "PostgreSQL bootstrap safety gates passed."

# A matching image path and service identity are not proof of ownership. The
# provisioner must refuse every pre-existing service before touching its ACLs.
$provisionerSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot "provision-postgresql-bootstrap-service.ps1") -Raw
if ($provisionerSource -notmatch '(?m)^\s*throw "Existing bootstrap service detected; refusing to adopt or modify it\."\s*$') {
 throw "Bootstrap provisioner must fail closed for every pre-existing service."
}
if ($provisionerSource -match '\$existing\.PathName|\$existing\.StartName') {
 throw "Bootstrap provisioner must not treat matching service metadata as ownership proof."
}
