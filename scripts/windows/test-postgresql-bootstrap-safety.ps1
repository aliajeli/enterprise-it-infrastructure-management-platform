$ErrorActionPreference="Stop"
$secret=ConvertTo-SecureString "synthetic-test-secret" -AsPlainText -Force
$bootstrap=@{
 PgHost="127.0.0.1";PgPort=5432;AdminUser="test_admin";AdminPassword=$secret
 DatabaseName="test_db";SchemaOwnerRole="test_owner";MigrationRole="test_migrator";MigrationPassword=$secret
 ApiRole="test_api";ApiPassword=$secret;WorkerRole="test_worker";WorkerPassword=$secret
}
$migration=@{
 InstallRoot=(Join-Path $env:TEMP "nonexistent-install");PgHost="127.0.0.1";PgPort=5432
 DatabaseName="test_db";MigrationRole="test_migrator";MigrationPassword=$secret
 SchemaOwnerRole="test_owner";ApiRole="test_api";WorkerRole="test_worker";AdminPassword=$secret;AdminUser="test_admin"
}
foreach($case in @(
 @{Script=(Join-Path $PSScriptRoot "bootstrap-postgresql-database.ps1");Arguments=$bootstrap},
 @{Script=(Join-Path $PSScriptRoot "invoke-postgresql-migrations.ps1");Arguments=$migration}
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
  $blocked=$_.Exception.Message -like '*disabled pending secure credential transport*'
 }
 if(-not $blocked){throw "Database mutation must be blocked until security review."}
}
$pf=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
. (Join-Path $PSScriptRoot "orchestrate-windows-services.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -ApiDatabaseUrl $secret -WorkerDatabaseUrl $secret -EdgeBindAddress "192.0.2.10" -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40)
$blocked=$false
try{Invoke-WindowsServiceOrchestration -Plan ([pscustomobject]@{}) -ApiDatabaseUrl $secret -WorkerDatabaseUrl $secret -Bootstrap @{} | Out-Null}catch{
 $blocked=$_.Exception.Message -like '*PostgreSQL bootstrap is disabled*no services were changed*'
}
if(-not $blocked){throw "Orchestration must reject bootstrap before preflight or service mutation."}
$blocked=$false
try{Invoke-WindowsServiceOrchestration -Plan ([pscustomobject]@{}) -ApiDatabaseUrl $secret -WorkerDatabaseUrl $secret | Out-Null}catch{
 $blocked=$_.Exception.Message -like '*Service orchestration is disabled*ownership verification*no services were changed*'
}
if(-not $blocked){throw "Orchestration without bootstrap must not adopt an unknown cluster."}
Write-Host "PostgreSQL bootstrap safety gates passed."
