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
  $output=''
  if($CaptureOutput){if(-not $out.Wait(5000)){throw 'Disposable test output did not close.'};$output=$out.GetAwaiter().GetResult()}
  return [pscustomobject]@{ExitCode=$child.ExitCode;Output=$output}
 }finally{$child.Dispose()}
}
$stage='initialize';$started=$false
try{
 $secret=ConvertTo-SecureString 'synthetic-admin-migration-test-72' -AsPlainText -Force
 try{
  $result=Invoke-ExperimentalInitDbStdin -Executable $initdb -DataPath $data -Password $secret -TimeoutSeconds 90
 }catch{
  # Preserve only fixed experiment substages, never child output or exceptions.
  if($_.Exception.Message -match '^Experimental initdb stdin operation failed at (credential-preparation|start-child|write-stdin|wait-child|restricted-reexec-error|child-exit-[0-9]+)\.$'){$stage='initialize-'+$Matches[1]}
  throw
 }
 if($result.status -ne 'ok'){throw 'Disposable initdb failed.'}
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
 Write-Host 'Extracted Prisma tooling applied and repeated disposable migrations under the intended schema owner; production migration remains disabled.'
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
