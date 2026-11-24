[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
 [Parameter(Mandatory=$true)][string]$PgHost,
 [Parameter(Mandatory=$true)][int]$PgPort,
 [Parameter(Mandatory=$true)][string]$AdminUser,
 [Parameter(Mandatory=$true)][Security.SecureString]$AdminPassword,
 [Parameter(Mandatory=$true)][string]$DatabaseName,
 [Parameter(Mandatory=$true)][string]$SchemaOwnerRole,
 [Parameter(Mandatory=$true)][string]$MigrationRole,
 [Parameter(Mandatory=$true)][Security.SecureString]$MigrationPassword,
 [Parameter(Mandatory=$true)][string]$ApiRole,
 [Parameter(Mandatory=$true)][Security.SecureString]$ApiPassword,
 [Parameter(Mandatory=$true)][string]$WorkerRole,
 [Parameter(Mandatory=$true)][Security.SecureString]$WorkerPassword
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function ConvertTo-PlainText([Security.SecureString]$Secure){
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
 try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
}
function Assert-SafeIdentifier([string]$Name,[string]$Label){
 if($Name -notmatch '^[A-Za-z][A-Za-z0-9_]{0,62}$'){throw "Unsafe SQL identifier for ${Label}."}
}
function Invoke-Psql([string]$User,[Security.SecureString]$Password,[string]$Db,[string]$Sql){
 $plain=$null;$envCopy=$null
 try{
  $plain=ConvertTo-PlainText $Password
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName="psql"
  foreach($a in @("--no-psqlrc","-v","ON_ERROR_STOP=1","-h",$PgHost,"-p",[string]$PgPort,"-U",$User,"-d",$Db,"-c",$Sql)){$psi.ArgumentList.Add($a)}
  $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.RedirectStandardInput=$false
  # Process-scoped env only; not persistent machine/user env.
  $psi.Environment["PGPASSWORD"]=$plain
  $p=[Diagnostics.Process]::Start($psi)
  $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync();$p.WaitForExit()
  $out=$outTask.GetAwaiter().GetResult();$err=$errTask.GetAwaiter().GetResult()
  if($p.ExitCode -ne 0){throw "psql failed for role $User against $Db. Exit=$($p.ExitCode)."}
  return $out
 }finally{
  $plain=$null
 }
}
function Invoke-PsqlScript([string]$User,[Security.SecureString]$Password,[string]$Db,[string]$Sql){
 # For multi-statement idempotent bootstrap; split not required, psql -c handles multiple statements.
 Invoke-Psql -User $User -Password $Password -Db $Db -Sql $Sql | Out-Null
}
function Escape-SqlLiteral([string]$Value){
 # Single-quote literal escaping for SQL; value must not contain null.
 if($Value.IndexOf([char]0) -ge 0){throw "Unsafe SQL literal."}
 return "'" + $Value.Replace("'","''") + "'"
}

foreach($pair in @(@($DatabaseName,"DatabaseName"),@($SchemaOwnerRole,"SchemaOwnerRole"),@($MigrationRole,"MigrationRole"),@($ApiRole,"ApiRole"),@($WorkerRole,"WorkerRole"))){
 Assert-SafeIdentifier -Name $pair[0] -Label $pair[1]
}
if($PgPort -lt 1 -or $PgPort -gt 65535){throw "Invalid PostgreSQL port."}

if($WhatIfPreference){
 [pscustomobject]@{status="whatif";database=$DatabaseName;schemaOwner=$SchemaOwnerRole;migrationRole=$MigrationRole;apiRole=$ApiRole;workerRole=$WorkerRole;mutated=$false} | ConvertTo-Json -Depth 4
 return
}
if(-not $PSCmdlet.ShouldProcess($DatabaseName,"Bootstrap PostgreSQL roles, database and grants idempotently")){return}

# Connect to postgres maintenance DB for role/database creation.
# Role/database creation is idempotent and verified.
$migrationPass=ConvertTo-PlainText $MigrationPassword
$apiPass=ConvertTo-PlainText $ApiPassword
$workerPass=ConvertTo-PlainText $WorkerPassword
try{
 $migLit=Escape-SqlLiteral $migrationPass
 $apiLit=Escape-SqlLiteral $apiPass
 $wrkLit=Escape-SqlLiteral $workerPass

 # Roles
 $roleSql=@"
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='$SchemaOwnerRole') THEN
  CREATE ROLE \"$SchemaOwnerRole\" NOLOGIN;
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='$MigrationRole') THEN
  CREATE ROLE \"$MigrationRole\" LOGIN NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER NOREPLICATION NOBYPASSRLS PASSWORD $migLit;
 ELSE
  ALTER ROLE \"$MigrationRole\" LOGIN NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER NOREPLICATION NOBYPASSRLS PASSWORD $migLit;
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='$ApiRole') THEN
  CREATE ROLE \"$ApiRole\" LOGIN NOCREATEDB NOCREATEROLE NOSUPERUSER NOREPLICATION NOBYPASSRLS PASSWORD $apiLit;
 ELSE
  ALTER ROLE \"$ApiRole\" LOGIN NOCREATEDB NOCREATEROLE NOSUPERUSER NOREPLICATION NOBYPASSRLS PASSWORD $apiLit;
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='$WorkerRole') THEN
  CREATE ROLE \"$WorkerRole\" LOGIN NOCREATEDB NOCREATEROLE NOSUPERUSER NOREPLICATION NOBYPASSRLS PASSWORD $wrkLit;
 ELSE
  ALTER ROLE \"$WorkerRole\" LOGIN NOCREATEDB NOCREATEROLE NOSUPERUSER NOREPLICATION NOBYPASSRLS PASSWORD $wrkLit;
 END IF;
END $$;
GRANT \"$SchemaOwnerRole\" TO \"$MigrationRole\" WITH INHERIT FALSE, SET TRUE;
ALTER ROLE \"$MigrationRole\" SET role='$SchemaOwnerRole';
"@
 Invoke-PsqlScript -User $AdminUser -Password $AdminPassword -Db "postgres" -Sql $roleSql

 # Database
 $dbExists=Invoke-Psql -User $AdminUser -Password $AdminPassword -Db "postgres" -Sql "SELECT 1 FROM pg_database WHERE datname=$(Escape-SqlLiteral $DatabaseName)"
 if($dbExists -notmatch '\b1\b'){
  # CREATE DATABASE cannot run inside DO/transaction block.
  Invoke-Psql -User $AdminUser -Password $AdminPassword -Db "postgres" -Sql "CREATE DATABASE `"$DatabaseName`" OWNER `"$SchemaOwnerRole`""
 }
 Invoke-PsqlScript -User $AdminUser -Password $AdminPassword -Db "postgres" -Sql "ALTER DATABASE `"$DatabaseName`" OWNER TO `"$SchemaOwnerRole`"; GRANT CONNECT ON DATABASE `"$DatabaseName`" TO `"$MigrationRole`", `"$ApiRole`", `"$WorkerRole`";"

 # Schema and grants in target DB
 $grantSql=@"
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO \"$ApiRole\", \"$WorkerRole\";
GRANT CREATE, USAGE ON SCHEMA public TO \"$SchemaOwnerRole\";
ALTER SCHEMA public OWNER TO \"$SchemaOwnerRole\";
"@
 Invoke-PsqlScript -User $AdminUser -Password $AdminPassword -Db $DatabaseName -Sql $grantSql

 # Table grants apply to existing objects (idempotent). Migration runner also applies default privileges.
 $tableGrantSql=@"
DO $$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['users','sessions','branches','user_branch_access','assets','switch_profiles','switch_ports','discovery_runs'] LOOP
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
   EXECUTE format('GRANT SELECT, INSERT, UPDATE ON TABLE public.%I TO %I', t, '$ApiRole');
  END IF;
 END LOOP;
 IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='audit_events') THEN
  EXECUTE 'GRANT INSERT ON TABLE public.audit_events TO "$ApiRole"';
 END IF;
 IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='port_observations') THEN
  EXECUTE 'GRANT SELECT, INSERT ON TABLE public.port_observations TO "$ApiRole"';
 END IF;
 IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='discovery_runs') THEN
  EXECUTE 'GRANT SELECT, UPDATE ON TABLE public.discovery_runs TO "$WorkerRole"';
 END IF;
END $$;
"@
 Invoke-PsqlScript -User $AdminUser -Password $AdminPassword -Db $DatabaseName -Sql $tableGrantSql

 [pscustomobject]@{status="ok";database=$DatabaseName;schemaOwner=$SchemaOwnerRole;migrationRole=$MigrationRole;apiRole=$ApiRole;workerRole=$WorkerRole;mutated=$true} | ConvertTo-Json -Depth 4
}finally{
 $migrationPass=$null;$apiPass=$null;$workerPass=$null
}
