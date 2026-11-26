# Real PostgreSQL acceptance for the database bootstrap capability: fresh
# creation, idempotent convergence, fail-closed rejection of foreign database
# and role state, uninitialized-cluster rejection, and no connection secret
# in psql process arguments. Requires an elevated Windows CI runner with
# network access for the pinned PostgreSQL payload staging.
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference=$false
if(-not $IsWindows -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw "Windows CI runner required."}
$bootstrapScript=Join-Path $PSScriptRoot "bootstrap-postgresql-database.ps1"
$stageScript=Join-Path $PSScriptRoot "stage-postgresql.ps1"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
$versionDigits=([guid]::NewGuid().ToString("N") -replace '[^0-9]','')
if($versionDigits.Length -lt 8){throw "Could not allocate a unique test version directory."}
$installRoot=Join-Path $pf ("EnterpriseIT\0.0."+ $versionDigits)
$dataBase=Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18"
$testRoot=Join-Path $dataBase ("bootstrap-db-"+[guid]::NewGuid().ToString("N"))
$data=Join-Path $testRoot "data"
$secretMarker="ci-db-bootstrap-"+[guid]::NewGuid().ToString("N")+"Aa1!"
$secret=ConvertTo-SecureString $secretMarker -AsPlainText -Force
$argvLog=Join-Path $env:RUNNER_TEMP ("eit-psql-argv-"+[guid]::NewGuid().ToString("N")+".log")
$createdInstall=$false
$createdTestRoot=$false
$pgProcess=$null
$argvEnvSet=$false
function Invoke-TestPsql {
 param([string]$PsqlExe,[string]$Sql,[string]$User="platform_admin",[string]$Database="postgres")
 $env:PGPASSWORD=$secretMarker
 try{
  $output=@($Sql | & $PsqlExe -X -q -t -A -v ON_ERROR_STOP=1 --connect-timeout=10 --host=127.0.0.1 --port=5432 --username=$User --dbname=$Database -f - 2>$null)
  if($LASTEXITCODE -ne 0){throw "Test psql failed with exit code $LASTEXITCODE."}
  return ($output -join [Environment]::NewLine)
 }finally{
  Remove-Item -Path env:PGPASSWORD -ErrorAction SilentlyContinue
 }
}
try{
 # Uninitialized cluster must fail closed before any psql invocation.
 $notInitialized=$false
 try{
  & $bootstrapScript -PgHost "127.0.0.1" -PgPort 5432 -AdminUser "ci_bootstrap_admin" -AdminPassword $secret -DatabaseName "ci_enterprise_it" -SchemaOwnerRole "ci_owner" -MigrationRole "ci_migrator" -MigrationPassword $secret -ApiRole "ci_api" -ApiPassword $secret -WorkerRole "ci_worker" -WorkerPassword $secret -DataRoot $data -InstallRoot $installRoot -Confirm:$false|Out-Null
 }catch{$notInitialized=$_.Exception.Message -like '*PostgreSQL cluster is not initialized*refusing database bootstrap*'}
 if(-not $notInitialized){throw "Bootstrap must fail closed before psql when the cluster is not initialized."}
 if(Test-Path -LiteralPath $argvLog){throw "Uninitialized-cluster rejection must not invoke psql."}

 # Stage the pinned PostgreSQL payload and initialize a disposable cluster.
 & $stageScript -InstallRoot $installRoot -CacheDirectory (Join-Path $env:RUNNER_TEMP "eit-pg-cache-bootstrap-db") -Confirm:$false|Out-Null
 $createdInstall=$true
 New-Item -ItemType Directory -Path $testRoot -Force|Out-Null
 $createdTestRoot=$true
 $initdb=Join-Path $installRoot "postgresql\pgsql\bin\initdb.exe"
 $initdbStart=[Diagnostics.ProcessStartInfo]::new()
 $initdbStart.FileName=$initdb
 $initdbStart.UseShellExecute=$false
 $initdbStart.CreateNoWindow=$true
 $initdbStart.RedirectStandardInput=$true
 $initdbStart.RedirectStandardOutput=$true
 $initdbStart.RedirectStandardError=$true
 foreach($argument in @("--pgdata=$data","--username=platform_admin","--auth=scram-sha-256","--pwprompt","--encoding=UTF8")){$initdbStart.ArgumentList.Add($argument)}
 # PostgreSQL 18 simple_prompt falls back to stdin only on the msys branch;
 # without these process-local overrides the restricted re-exec may acquire a
 # console and block on interactive input. Never permit an inherited
 # PG_RESTRICT_EXEC (or any other PG* value) to alter re-exec behavior.
 # This mirrors the dedicated bootstrap service and the reviewed stdin helper.
 foreach($key in @($initdbStart.Environment.Keys|Where-Object{$_ -like 'PG*'})){$null=$initdbStart.Environment.Remove($key)}
 $initdbStart.Environment['OSTYPE']='msys'
 $initdbStart.Environment['LC_ALL']='C'
 $initdbProcess=[Diagnostics.Process]::Start($initdbStart)
 if($null -eq $initdbProcess){throw "Fixture initdb did not start."}
 $initdbOutTask=$initdbProcess.StandardOutput.ReadToEndAsync()
 $initdbErrTask=$initdbProcess.StandardError.ReadToEndAsync()
 $initdbInput=([Text.UTF8Encoding]::new($false,$true).GetBytes($secretMarker+"`n"+$secretMarker+"`n"))
 $initdbProcess.StandardInput.BaseStream.Write($initdbInput,0,$initdbInput.Length)
 $initdbProcess.StandardInput.Close()
 if(-not $initdbProcess.WaitForExit(300000)){try{$initdbProcess.Kill($true)}catch{};throw "Fixture initdb timed out."}
 $initdbExitCode=$initdbProcess.ExitCode
 $null=$initdbOutTask.GetAwaiter().GetResult()
 $null=$initdbErrTask.GetAwaiter().GetResult()
 $initdbProcess.Dispose()
 if($initdbExitCode -ne 0){throw "Fixture initdb failed."}
 if(-not(Test-Path -LiteralPath (Join-Path $data "PG_VERSION") -PathType Leaf)){throw "Fixture initdb did not create a cluster."}

 # Mirror the service's configuration hardening; the SCM test proves the
 # service applies these exact pins to a real service-owned cluster.
 [IO.File]::AppendAllText((Join-Path $data "postgresql.conf"),("`nlisten_addresses = '127.0.0.1'`nport = 5432`n"),[Text.UTF8Encoding]::new($false))
 [IO.File]::AppendAllText((Join-Path $data "pg_hba.conf"),("`nhost`tall`tall`t0.0.0.0/0`treject`nhost`tall`tall`t::/0`treject`n"),[Text.UTF8Encoding]::new($false))

 if(Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue){throw "TCP 5432 is occupied; cannot start the fixture cluster."}
 $postgres=Join-Path $installRoot "postgresql\pgsql\bin\postgres.exe"
 $pgProcess=Start-Process -FilePath $postgres -ArgumentList @("-D",$data) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $testRoot "postgres.out.log") -RedirectStandardError (Join-Path $testRoot "postgres.err.log")
 $pgIsready=Join-Path $installRoot "postgresql\pgsql\bin\pg_isready.exe"
 $ready=$false
 for($i=0;$i -lt 60;$i++){
  & $pgIsready -h 127.0.0.1 -p 5432 -t 2|Out-Null
  if($LASTEXITCODE -eq 0){$ready=$true;break}
  if($pgProcess.HasExited){throw "Fixture postgres exited before becoming ready."}
  Start-Sleep -Seconds 1
 }
 if(-not $ready){throw "Fixture cluster did not become ready on 127.0.0.1:5432."}

 $psql=Join-Path $installRoot "postgresql\pgsql\bin\psql.exe"
 # psql argv recorder: the capability must never pass a secret as a process
 # argument. The wrapper forwards every invocation to the real client.
 $wrapper=Join-Path $testRoot "psql-wrapper.cmd"
 $wrapperBody="@echo OFF`r`n>>`"%EIT_PSQL_ARGV_LOG%`" echo %*`r`n`"$psql`" %*`r`n"
 [IO.File]::WriteAllText($wrapper,$wrapperBody,[Text.UTF8Encoding]::new($false))
 $parameters=@{
  PgHost="127.0.0.1";PgPort=5432;AdminUser="ci_bootstrap_admin";AdminPassword=$secret
  DatabaseName="ci_enterprise_it";SchemaOwnerRole="ci_owner";MigrationRole="ci_migrator";MigrationPassword=$secret
  ApiRole="ci_api";ApiPassword=$secret;WorkerRole="ci_worker";WorkerPassword=$secret
  DataRoot=$data;InstallRoot=$installRoot;PsqlPath=$wrapper
 }
 $env:EIT_PSQL_ARGV_LOG=$argvLog
 $argvEnvSet=$true

 # Fresh creation: all five roles plus the owned database.
 $first=& $bootstrapScript @parameters -Confirm:$false|ConvertFrom-Json
 if($first.status -ne "ok" -or -not $first.databaseCreated){throw "Fresh bootstrap must create the database."}
 if(@($first.rolesCreated).Count -ne 5){throw "Fresh bootstrap must create all five deployment roles."}
 $owner=Invoke-TestPsql -PsqlExe $psql -Sql "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='ci_enterprise_it';"
 if($owner.Trim() -cne "ci_owner"){throw "Fresh bootstrap must own the database with the schema owner role."}
 $roleCount=Invoke-TestPsql -PsqlExe $psql -Sql "SELECT count(*) FROM pg_roles WHERE rolname IN ('ci_bootstrap_admin','ci_owner','ci_migrator','ci_api','ci_worker');"
 if($roleCount.Trim() -cne "5"){throw "Fresh bootstrap must create all five deployment roles."}
 $privileged=Invoke-TestPsql -PsqlExe $psql -Sql "SELECT count(*) FROM pg_roles WHERE rolname IN ('ci_owner','ci_migrator','ci_api','ci_worker') AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolbypassrls OR rolreplication);"
 if($privileged.Trim() -cne "0"){throw "Bootstrap roles must carry no privileged attributes."}
 $ownerLogin=Invoke-TestPsql -PsqlExe $psql -Sql "SELECT rolcanlogin FROM pg_roles WHERE rolname='ci_owner';"
 if($ownerLogin.Trim() -cne "f"){throw "Schema owner role must not be a login role."}
 # A fresh SCRAM connection as a runtime role proves the password converged.
 Invoke-TestPsql -PsqlExe $psql -Sql "SELECT 1;" -User "ci_api" -Database "ci_enterprise_it"|Out-Null

 # Idempotent second run converges without recreating the database.
 $second=& $bootstrapScript @parameters -Confirm:$false|ConvertFrom-Json
 if($second.status -ne "ok" -or $second.databaseCreated){throw "Second bootstrap run must be idempotent."}
 if(@($second.rolesConverged).Count -ne 4){throw "Second bootstrap run must converge the four login roles."}

 # Foreign-owned database must be rejected before any mutation: a role left
 # in a mismatched state proves no statement executed.
 Invoke-TestPsql -PsqlExe $psql -Sql "ALTER ROLE ci_api NOLOGIN;"|Out-Null
 Invoke-TestPsql -PsqlExe $psql -Sql "DROP DATABASE ci_enterprise_it;"|Out-Null
 Invoke-TestPsql -PsqlExe $psql -Sql "CREATE DATABASE ci_enterprise_it OWNER platform_admin;"|Out-Null
 $foreignRejected=$false
 try{& $bootstrapScript @parameters -Confirm:$false|Out-Null}catch{$foreignRejected=$_.Exception.Message -like '*does not match the expected owner*refusing to adopt*'}
 if(-not $foreignRejected){throw "Foreign-owned database must be rejected fail-closed."}
 $apiLogin=Invoke-TestPsql -PsqlExe $psql -Sql "SELECT rolcanlogin FROM pg_roles WHERE rolname='ci_api';"
 if($apiLogin.Trim() -cne "f"){throw "Foreign-database rejection must run before any role mutation."}
 $foreignOwner=Invoke-TestPsql -PsqlExe $psql -Sql "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='ci_enterprise_it';"
 if($foreignOwner.Trim() -cne "platform_admin"){throw "Foreign database must remain untouched after rejection."}

 # Role-attribute mismatch must be rejected and must not create the missing
 # database on the way out.
 Invoke-TestPsql -PsqlExe $psql -Sql "DROP DATABASE ci_enterprise_it;"|Out-Null
 $roleRejected=$false
 try{& $bootstrapScript @parameters -Confirm:$false|Out-Null}catch{$roleRejected=$_.Exception.Message -like '*role does not match the expected bootstrap definition*refusing to adopt*'}
 if(-not $roleRejected){throw "Foreign role state must be rejected fail-closed."}
 $dbStillMissing=Invoke-TestPsql -PsqlExe $psql -Sql "SELECT count(*) FROM pg_database WHERE datname='ci_enterprise_it';"
 if($dbStillMissing.Trim() -cne "0"){throw "Role rejection must not create the database."}

 # The argv recorder captured every bootstrap psql invocation and no line
 # contains the connection secret.
 Remove-Item -Path env:EIT_PSQL_ARGV_LOG -ErrorAction SilentlyContinue
 $argvEnvSet=$false
 if(-not(Test-Path -LiteralPath $argvLog)){throw "psql argv recorder was never invoked."}
 $argvContent=[IO.File]::ReadAllText($argvLog)
 if($argvContent -notmatch "ON_ERROR_STOP"){throw "psql argv recorder did not capture bootstrap invocations."}
 if($argvContent -match [regex]::Escape($secretMarker)){throw "Bootstrap passed a secret through psql process arguments."}
 Write-Host "PostgreSQL database bootstrap capability tests passed."
}finally{
 if($argvEnvSet){Remove-Item -Path env:EIT_PSQL_ARGV_LOG -ErrorAction SilentlyContinue}
 if($null -ne $pgProcess){
  try{
   if(-not $pgProcess.HasExited){Stop-Process -Id $pgProcess.Id -Force -ErrorAction SilentlyContinue;$pgProcess.WaitForExit(15000)|Out-Null}
  }catch{}
  $pgProcess.Dispose()
 }
 if($createdTestRoot -and (Test-Path -LiteralPath $testRoot)){
  for($attempt=0;$attempt -lt 5 -and (Test-Path -LiteralPath $testRoot);$attempt++){
   Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
   if(Test-Path -LiteralPath $testRoot){Start-Sleep -Seconds 1}
  }
 }
 if($createdInstall -and (Test-Path -LiteralPath $installRoot)){Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue}
 if(Test-Path -LiteralPath $argvLog){Remove-Item -LiteralPath $argvLog -Force -ErrorAction SilentlyContinue}
}
# Leftover native exit codes from negative-path checks must not become the
# step's process exit code.
$global:LASTEXITCODE=0
