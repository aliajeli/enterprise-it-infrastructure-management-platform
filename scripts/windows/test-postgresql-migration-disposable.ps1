# Disposable Windows CI experiment against the extracted payload only.
# Synthetic credentials and loopback; NOT a production bootstrap or migration.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PayloadRoot,[Parameter(Mandatory=$true)][string]$WorkRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $env:RUNNER_TEMP){throw 'This experiment requires a disposable Windows CI runner.'}
$payload=[IO.Path]::GetFullPath($PayloadRoot)
$work=[IO.Path]::GetFullPath($WorkRoot)
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar)
if(-not $work.StartsWith(($runner+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'Disposable work root must be beneath RUNNER_TEMP.'}
$data=Join-Path $work 'migration-disposable-data'
if(Test-Path -LiteralPath $data){throw 'Refusing to adopt an existing PostgreSQL data directory.'}
$bin=Join-Path $payload 'postgresql\pgsql\bin'
$initdb=Join-Path $bin 'initdb.exe';$pgctl=Join-Path $bin 'pg_ctl.exe';$psql=Join-Path $bin 'psql.exe'
$node=Join-Path $payload 'runtime\node.exe';$prisma=Join-Path $payload 'migration-tool\node_modules\prisma\build\index.js'
$config=Join-Path $payload 'migration-tool\prisma.config.ts'
foreach($file in @($initdb,$pgctl,$psql,$node,$prisma,$config)){if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw 'Disposable test payload is incomplete.'}}
. (Join-Path $PSScriptRoot 'experimental-initdb-stdin.ps1')
function Invoke-TestChild([string]$Executable,[string[]]$Arguments,[hashtable]$Environment,[string]$InputText,[bool]$CaptureOutput=$false){
 $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$Executable
 foreach($arg in $Arguments){$start.ArgumentList.Add($arg)}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 # Do not inherit unrelated credentials; only explicitly supplied synthetic
 # values exist in the ephemeral child process environment.
 foreach($name in @('DATABASE_URL','PGPASSWORD','PGSERVICE','PGPASSFILE')){$null=$start.Environment.Remove($name)}
 foreach($name in $Environment.Keys){$start.Environment[$name]=[string]$Environment[$name]}
 $child=[Diagnostics.Process]::Start($start)
 try{
  $out=$child.StandardOutput.ReadToEndAsync();$err=$child.StandardError.ReadToEndAsync()
  if($null -ne $InputText){$child.StandardInput.Write($InputText)}
  $child.StandardInput.Close()
  if(-not $child.WaitForExit(120000)){try{$child.Kill($true);$child.WaitForExit()}catch{};throw 'Disposable test process timed out.'}
  $output='';$diagnostic=''
  if($CaptureOutput){
   if(-not $out.Wait(5000) -or -not $err.Wait(5000)){throw 'Disposable test output did not close.'}
   $output=$out.GetAwaiter().GetResult();$diagnostic=$err.GetAwaiter().GetResult()
  }
  return [pscustomobject]@{ExitCode=$child.ExitCode;Output=$output;Diagnostic=$diagnostic}
 }finally{$child.Dispose()}
}
$stage='prepare-synthetic-secret';$started=$false
try{
 $secret=ConvertTo-SecureString 'synthetic-admin-migration-test-72' -AsPlainText -Force
 $stage='invoke-initdb'
 try{
  $initResults=@(Invoke-ExperimentalInitDbStdin -Executable $initdb -DataPath $data -Password $secret -TimeoutSeconds 90)
 }catch{
  # Preserve only fixed experiment substages, never child output or exceptions.
  if($_.Exception.Message -match '^Experimental initdb stdin operation failed at (credential-preparation|start-child|write-stdin|wait-child|restricted-reexec-error|child-exit-[0-9]+)\.$'){$stage='initialize-'+$Matches[1]}
  elseif($_.Exception -is [Management.Automation.CommandNotFoundException]){$stage='initialize-command-not-found'}
  elseif($_.Exception -is [Management.Automation.ParameterBindingException]){$stage='initialize-parameter-binding'}
  else{$stage='initialize-other'}
  throw
 }
 $stage='check-initdb-result-count'
 if($initResults.Count -ne 1){throw 'Disposable initdb returned an unexpected result count.'}
 $stage='check-initdb-result-status'
 if($null -eq $initResults[0].PSObject.Properties['status'] -or $initResults[0].status -ne 'ok'){throw 'Disposable initdb failed.'}
 $stage='allocate-loopback-port'
 $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
 try{$listener.Start();$port=([Net.IPEndPoint]$listener.LocalEndpoint).Port}finally{$listener.Stop()}
 $stage='start-loopback'
 $server=Invoke-TestChild $pgctl @('-D',$data,'-l',(Join-Path $work 'migration-postgres-test.log'),'-o',("-h 127.0.0.1 -p "+$port),'-w','start') @{} $null
 if($server.ExitCode -ne 0){throw 'Disposable PostgreSQL failed to start.'}
 $started=$true
 $adminEnv=@{PGPASSWORD='synthetic-admin-migration-test-72'}
 $base=@('-X','-w','-h','127.0.0.1','-p',[string]$port,'-U','platform_admin','-d','postgres','-v','ON_ERROR_STOP=1','-q')
 # SQL containing a synthetic password goes through the child stdin, never
 # a command argument, persistent environment, file or log.
 $sql=@'
CREATE ROLE fixture_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE fixture_migrator LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD 'synthetic-migrator-test-73';
GRANT fixture_owner TO fixture_migrator WITH INHERIT FALSE, SET TRUE;
ALTER ROLE fixture_migrator SET role = 'fixture_owner';
CREATE DATABASE fixture_database OWNER fixture_owner;
'@
 $stage='create-fixture-roles'
 $setup=Invoke-TestChild $psql $base $adminEnv ($sql+"`n")
 if($setup.ExitCode -ne 0){throw 'Disposable role setup failed.'}
 $migrationEnv=@{
  DATABASE_URL=('postgresql://fixture_migrator:synthetic-migrator-test-73@127.0.0.1:'+$port+'/fixture_database?schema=public')
  PRISMA_ENGINES_MIRROR='http://127.0.0.1:9'
  PRISMA_HIDE_UPDATE_MESSAGE='1'
 }
 $stage='apply-migrations'
 $prismaArgs=@($prisma,'migrate','deploy','--config',$config)
 foreach($attempt in 1..2){
  $deploy=Invoke-TestChild $node $prismaArgs $migrationEnv $null
  if($deploy.ExitCode -ne 0){throw 'Disposable Prisma migration failed.'}
 }
 $stage='verify-identity-and-ownership'
 $count=@(Get-ChildItem -LiteralPath (Join-Path $payload 'packages\database\prisma\migrations') -Directory).Count
 if($count -lt 1){throw 'Packaged migrations are absent.'}
 $query=@"
SELECT session_user='fixture_migrator'
 AND current_user='fixture_owner'
 AND (SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname=current_database())='fixture_owner'
 AND (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='public._prisma_migrations'::regclass)='fixture_owner'
 AND (SELECT count(*) FROM public._prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL)=$count
 AND NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','i','S','v','m','f') AND pg_get_userbyid(c.relowner)<>'fixture_owner')
 AND NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typtype='e' AND pg_get_userbyid(t.typowner)<>'fixture_owner')
 AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND pg_get_userbyid(p.proowner)<>'fixture_owner');
"@
 $checkArgs=@('-X','-w','-h','127.0.0.1','-p',[string]$port,'-U','fixture_migrator','-d','fixture_database','-v','ON_ERROR_STOP=1','-t','-A','-q')
 $check=Invoke-TestChild $psql $checkArgs @{PGPASSWORD='synthetic-migrator-test-73'} ($query+"`n") $true
 if($check.ExitCode -ne 0 -or $check.Output.Trim() -cne 't'){throw 'Disposable migration ownership or repeat check failed.'}
 # Simulate a failed migration against this disposable database only. The
 # migration tree below is a scratch copy; the immutable extracted payload is
 # never changed. Recovery is explicit operator-like resolve, never automatic
 # production repair or schema destruction.
 $stage='prepare-failed-migration-fixture'
 $scratch=Join-Path $work 'migration-failure-fixture'
 New-Item -ItemType Directory -Path $scratch -ErrorAction Stop|Out-Null
 $scratchMigrations=Join-Path $scratch 'migrations'
 Copy-Item -LiteralPath (Join-Path $payload 'packages\database\prisma\migrations') -Destination $scratchMigrations -Recurse
 $fixtureName='99990101000000_synthetic_failure'
 $fixtureDir=Join-Path $scratchMigrations $fixtureName
 New-Item -ItemType Directory -Path $fixtureDir -ErrorAction Stop|Out-Null
 $fixtureSql=Join-Path $fixtureDir 'migration.sql'
 # Explicit COMMIT leaves a deliberately partial effect before the error;
 # never assume all PostgreSQL migration scripts are transactionally atomic.
 $brokenSql=@'
BEGIN;
CREATE TABLE public.fixture_partial (id integer PRIMARY KEY);
INSERT INTO public.fixture_partial VALUES (42);
COMMIT;
SELECT 1 / 0;
'@
 [IO.File]::WriteAllText($fixtureSql,($brokenSql+"`n"),[Text.UTF8Encoding]::new($false))
 $scratchConfig=Join-Path $scratch 'prisma.config.ts'
 $schemaJson=([string](Join-Path $payload 'packages\database\prisma\schema.prisma')).Replace('\','/') | ConvertTo-Json -Compress
 $migrationsJson=([string]$scratchMigrations).Replace('\','/') | ConvertTo-Json -Compress
 # The config contains only paths and reads the synthetic URL from the child
 # process environment. It does not embed a database URL or credential.
 [IO.File]::WriteAllText($scratchConfig,("export default { schema: $schemaJson, migrations: { path: $migrationsJson }, datasource: { url: process.env.DATABASE_URL } };`n"),[Text.UTF8Encoding]::new($false))
 $preserveSql="CREATE TABLE public.fixture_preserve (id integer PRIMARY KEY); INSERT INTO public.fixture_preserve VALUES (41);"
 $preserve=Invoke-TestChild $psql $checkArgs @{PGPASSWORD='synthetic-migrator-test-73'} ($preserveSql+"`n") $true
 if($preserve.ExitCode -ne 0){throw 'Could not prepare disposable migration preservation fixture.'}
 $stage='verify-failed-migration'
 $fixtureArgs=@($prisma,'migrate','deploy','--config',$scratchConfig)
 $failure=Invoke-TestChild $node $fixtureArgs $migrationEnv $null $true
 if($failure.ExitCode -eq 0 -or (($failure.Output+$failure.Diagnostic) -notmatch 'P3018')){throw 'Expected Prisma migration failure was not observed.'}
 $verifyFailed=@"
SELECT (SELECT count(*) FROM public._prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL)=$count
 AND (SELECT count(*) FROM public._prisma_migrations WHERE migration_name='$fixtureName' AND finished_at IS NULL AND rolled_back_at IS NULL)=1
 AND (SELECT count(*) FROM public.fixture_preserve WHERE id=41)=1
 AND (SELECT count(*) FROM public.fixture_partial WHERE id=42)=1
 AND (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='public.fixture_partial'::regclass)='fixture_owner';
"@
 $failedState=Invoke-TestChild $psql $checkArgs @{PGPASSWORD='synthetic-migrator-test-73'} ($verifyFailed+"`n") $true
 if($failedState.ExitCode -ne 0 -or $failedState.Output.Trim() -cne 't'){throw 'Failed migration did not preserve expected evidence and data.'}
 $stage='verify-failed-migration-blocks-retry'
 $retry=Invoke-TestChild $node $fixtureArgs $migrationEnv $null $true
 if($retry.ExitCode -eq 0 -or (($retry.Output+$retry.Diagnostic) -notmatch 'P3009')){throw 'Prisma did not refuse a retry with a failed migration.'}
 $stage='resolve-synthetic-failure-explicitly'
 $resolveArgs=@($prisma,'migrate','resolve','--rolled-back',$fixtureName,'--config',$scratchConfig)
 $resolve=Invoke-TestChild $node $resolveArgs $migrationEnv $null $true
 if($resolve.ExitCode -ne 0){throw 'Explicit synthetic migration rollback resolution failed.'}
 # This modified scratch migration represents explicit operator-reviewed
 # reconciliation after the partial effects above have been inspected. It is
 # not an automatic repair strategy for a real migration or production data.
 [IO.File]::WriteAllText($fixtureSql,"CREATE TABLE public.fixture_recovered (id integer PRIMARY KEY);`n",[Text.UTF8Encoding]::new($false))
 $stage='verify-explicit-migration-recovery'
 foreach($attempt in 1..2){
  $resumed=Invoke-TestChild $node $fixtureArgs $migrationEnv $null $true
  if($resumed.ExitCode -ne 0){throw 'Explicit disposable migration recovery failed.'}
 }
 $verifyRecovered=@"
SELECT (SELECT count(*) FROM public._prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL)=($count+1)
 AND (SELECT count(*) FROM public._prisma_migrations WHERE migration_name='$fixtureName' AND rolled_back_at IS NOT NULL)=1
 AND (SELECT count(*) FROM public.fixture_preserve WHERE id=41)=1
 AND (SELECT count(*) FROM public.fixture_partial WHERE id=42)=1
 AND (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='public.fixture_partial'::regclass)='fixture_owner'
 AND (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='public.fixture_recovered'::regclass)='fixture_owner';
"@
 $recovered=Invoke-TestChild $psql $checkArgs @{PGPASSWORD='synthetic-migrator-test-73'} ($verifyRecovered+"`n") $true
 if($recovered.ExitCode -ne 0 -or $recovered.Output.Trim() -cne 't'){throw 'Explicit recovery did not preserve fixture data and migration ownership.'}
 # These SQL grants model the existing Linux CI privilege matrix only. They
 # are never wired to production provisioning and do not establish production
 # credential handling, account ownership, or service-SID acceptance.
 $grantSql=@'
CREATE ROLE fixture_api LOGIN PASSWORD 'synthetic-api-test-74' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE fixture_worker LOGIN PASSWORD 'synthetic-worker-test-75' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
REVOKE CONNECT ON DATABASE fixture_database FROM PUBLIC;
GRANT CONNECT ON DATABASE fixture_database TO fixture_migrator, fixture_api, fixture_worker;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO fixture_api, fixture_worker;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, fixture_api, fixture_worker;
GRANT SELECT, INSERT, UPDATE ON public.users, public.sessions, public.branches, public.user_branch_access, public.assets, public.switch_profiles, public.switch_ports, public.discovery_runs TO fixture_api;
GRANT INSERT ON public.audit_events TO fixture_api;
GRANT SELECT, INSERT ON public.port_observations TO fixture_api;
GRANT SELECT, UPDATE ON public.discovery_runs TO fixture_worker;
'@
 $stage='create-fixture-runtime-grants'
 $grantArgs=@('-X','-w','-h','127.0.0.1','-p',[string]$port,'-U','platform_admin','-d','fixture_database','-v','ON_ERROR_STOP=1','-q')
 $grants=Invoke-TestChild $psql $grantArgs $adminEnv ($grantSql+"`n")
 if($grants.ExitCode -ne 0){throw 'Disposable runtime grant fixture failed.'}
 $stage='verify-runtime-grants'
 $cases=@(
  @{role='fixture_api';password='synthetic-api-test-74';sql='SELECT * FROM public.users LIMIT 0;';allow=$true},
  @{role='fixture_api';password='synthetic-api-test-74';sql="INSERT INTO public.audit_events (id, actor_type, action, object_type, outcome) VALUES (gen_random_uuid(), 'SYSTEM', 'PRIVILEGE_TEST', 'test', 'SUCCESS');";allow=$true},
  @{role='fixture_api';password='synthetic-api-test-74';sql='SELECT * FROM public.recovery_codes LIMIT 0;';allow=$false},
  @{role='fixture_api';password='synthetic-api-test-74';sql='UPDATE public.audit_events SET action=action;';allow=$false},
  @{role='fixture_api';password='synthetic-api-test-74';sql='SELECT * FROM public._prisma_migrations LIMIT 0;';allow=$false},
  @{role='fixture_api';password='synthetic-api-test-74';sql='CREATE TABLE public.fixture_api_forbidden(id integer);';allow=$false},
  @{role='fixture_api';password='synthetic-api-test-74';sql='ALTER TABLE public.users ADD COLUMN privilege_probe integer;';allow=$false},
  @{role='fixture_api';password='synthetic-api-test-74';sql='TRUNCATE public.users;';allow=$false},
  @{role='fixture_api';password='synthetic-api-test-74';sql='SET ROLE fixture_owner;';allow=$false},
  @{role='fixture_worker';password='synthetic-worker-test-75';sql='SELECT * FROM public.discovery_runs LIMIT 0;';allow=$true},
  @{role='fixture_worker';password='synthetic-worker-test-75';sql='UPDATE public.discovery_runs SET heartbeat_at=heartbeat_at WHERE false;';allow=$true},
  @{role='fixture_worker';password='synthetic-worker-test-75';sql='SELECT * FROM public.users LIMIT 0;';allow=$false},
  @{role='fixture_worker';password='synthetic-worker-test-75';sql='DELETE FROM public.discovery_runs;';allow=$false},
  @{role='fixture_worker';password='synthetic-worker-test-75';sql='SELECT * FROM public._prisma_migrations LIMIT 0;';allow=$false},
  @{role='fixture_worker';password='synthetic-worker-test-75';sql='CREATE ROLE fixture_forbidden;';allow=$false},
  @{role='fixture_worker';password='synthetic-worker-test-75';sql='ALTER TABLE public.discovery_runs ADD COLUMN privilege_probe integer;';allow=$false},
  @{role='fixture_worker';password='synthetic-worker-test-75';sql='TRUNCATE public.discovery_runs;';allow=$false},
  @{role='fixture_worker';password='synthetic-worker-test-75';sql='SET ROLE fixture_owner;';allow=$false}
 )
 foreach($case in $cases){
  $roleArgs=@('-X','-w','-h','127.0.0.1','-p',[string]$port,'-U',[string]$case.role,'-d','fixture_database','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-q')
  $outcome=Invoke-TestChild $psql $roleArgs @{PGPASSWORD=[string]$case.password} ([string]$case.sql+"`n") $true
  if(($outcome.ExitCode -eq 0) -ne [bool]$case.allow){throw 'Disposable runtime privilege assertion failed.'}
  # Require insufficient_privilege (42501); a syntax, schema, connection, or
  # unrelated SQL error is not evidence that access controls denied the query.
  # Diagnostics stay in memory and are never printed.
  if(-not [bool]$case.allow -and $outcome.Diagnostic -notmatch 'ERROR:\s+42501:'){throw 'Disposable runtime denial had an unexpected SQLSTATE.'}
 }
 Write-Host 'Disposable migrations passed ownership, failure/retry blocking, explicit synthetic resolution and runtime privilege checks; production migration remains disabled.'

}catch{
 throw "Disposable PostgreSQL migration experiment failed at $stage."
}finally{
 if($started -or (Test-Path -LiteralPath (Join-Path $data 'postmaster.pid'))){
  try{
   $stop=Invoke-TestChild $pgctl @('-D',$data,'-m','immediate','-w','stop') @{} $null
   if($stop.ExitCode -ne 0){throw 'PostgreSQL stop failed.'}
  }catch{
   [IO.File]::WriteAllText((Join-Path $work 'DO_NOT_DELETE_RUNNING_POSTGRES'),'Synthetic server stop failed; retain files for runner cleanup.')
   throw 'Disposable PostgreSQL migration experiment could not stop its server.'
  }
 }
}
