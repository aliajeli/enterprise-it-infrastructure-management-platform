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
 [Parameter(Mandatory=$true)][Security.SecureString]$WorkerPassword,
 [string]$DataRoot=(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data"),
 [string]$InstallRoot="",
 [string]$PsqlPath=""
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
# Native psql exit codes must not become terminating errors from stderr
# redirection; failure is decided below from the exit code alone so no client
# output (which may quote a rejected statement) can reach logs or messages.
$PSNativeCommandUseErrorActionPreference=$false
# Validation is shared with the migration entry point and does not contact the
# server. It is not cluster identity or ownership verification.
. (Join-Path $PSScriptRoot 'postgresql-deployment-inputs.ps1')
Assert-PostgreSqlDeploymentInputs -PgHost $PgHost -PgPort $PgPort -DatabaseName $DatabaseName -AdminUser $AdminUser -SchemaOwnerRole $SchemaOwnerRole -MigrationRole $MigrationRole -ApiRole $ApiRole -WorkerRole $WorkerRole

if($WhatIfPreference){[pscustomobject]@{status="whatif";database=$DatabaseName;mutated=$false}|ConvertTo-Json -Depth 4;return}

# Capability prerequisites: fail closed before any server contact. The
# cluster must be initialized by the dedicated bootstrap pipeline with the
# hardened loopback configuration; the staged payload must carry psql.
. (Join-Path $PSScriptRoot 'postgresql-cluster-identity.ps1')
Assert-PostgreSqlClusterInitialized -DataRoot $DataRoot
if([string]::IsNullOrWhiteSpace($InstallRoot)){throw "PostgreSQL bootstrap requires the staged payload install root."}
# PsqlPath is a test-instrumentation seam; production callers rely on the
# staged payload path derived from InstallRoot.
$psql=$PsqlPath
if([string]::IsNullOrWhiteSpace($psql)){$psql=Join-Path $InstallRoot "postgresql\pgsql\bin\psql.exe"}
if(-not(Test-Path -LiteralPath $psql -PathType Leaf)){throw "psql.exe is missing from the staged PostgreSQL payload."}
if(-not $PSCmdlet.ShouldProcess($DatabaseName,"Create or verify PostgreSQL bootstrap roles and database")){[pscustomobject]@{status="skipped";database=$DatabaseName;mutated=$false}|ConvertTo-Json -Depth 4;return}

# The connector is the initdb superuser created by the dedicated bootstrap
# service. AdminPassword is that same operator-supplied bootstrap secret; it
# is never written to a file, never placed in process arguments and never
# included in a thrown message.
$superuser="platform_admin"

function ConvertTo-BootstrapPasswordText {
 param([Security.SecureString]$Secure)
 $ptr=[IntPtr]::Zero;$chars=$null
 try{
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  $chars=[char[]]::new($Secure.Length)
  [Runtime.InteropServices.Marshal]::Copy($ptr,$chars,0,$Secure.Length)
  if([Array]::IndexOf($chars,[char]0) -ge 0 -or [Array]::IndexOf($chars,[char]10) -ge 0 -or [Array]::IndexOf($chars,[char]13) -ge 0){throw "PostgreSQL bootstrap password contains unsupported characters."}
  return (-join $chars)
 }finally{
  if($chars){[Array]::Clear($chars,0,$chars.Length)}
  if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 }
}
function ConvertTo-SqlStringLiteral {
 param([string]$Value)
 return "'"+($Value.Replace("'","''"))+"'"
}
function Invoke-BootstrapPsql {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory=$true)][string]$PsqlPath,
  [Parameter(Mandatory=$true)][string]$ConnectionPassword,
  [Parameter(Mandatory=$true)][string[]]$Arguments,
  [Parameter(Mandatory=$true)][string]$Sql,
  # Diagnostic label only: it never carries SQL text or secret material, but
  # it identifies which client invocation failed in fail-closed throws.
  [Parameter(Mandatory=$true)][string]$Stage
 )
 if($Sql.Length -gt 32768){throw "PostgreSQL bootstrap SQL payload is too large."}
 $hadPrevious=$null -ne (Get-Item -Path env:PGPASSWORD -ErrorAction SilentlyContinue)
 $previous=$env:PGPASSWORD
 $hadPreviousTimeout=$null -ne (Get-Item -Path env:PGCONNECT_TIMEOUT -ErrorAction SilentlyContinue)
 $previousTimeout=$env:PGCONNECT_TIMEOUT
 $output=@();$exitCode=-1
 try{
  # Connection secret only via the child environment (never argv, never a
  # file); SQL text only via stdin. stderr is discarded because PostgreSQL
  # error text may quote the rejected statement. connect_timeout is a libpq
  # parameter (PGCONNECT_TIMEOUT), not a psql option — psql rejects
  # --connect-timeout outright.
  $env:PGPASSWORD=$ConnectionPassword
  $env:PGCONNECT_TIMEOUT="10"
  $output=@($Sql | & $PsqlPath @Arguments 2>$null)
  $exitCode=$LASTEXITCODE
 }finally{
  if($hadPrevious){$env:PGPASSWORD=$previous}else{Remove-Item -Path env:PGPASSWORD -ErrorAction SilentlyContinue}
  if($hadPreviousTimeout){$env:PGCONNECT_TIMEOUT=$previousTimeout}else{Remove-Item -Path env:PGCONNECT_TIMEOUT -ErrorAction SilentlyContinue}
 }
 if($exitCode -ne 0){throw "PostgreSQL bootstrap client failed at stage '$Stage' with exit code $exitCode."}
 return ($output -join [Environment]::NewLine)
}

$adminPasswordText=ConvertTo-BootstrapPasswordText -Secure $AdminPassword
$migrationPasswordText=ConvertTo-BootstrapPasswordText -Secure $MigrationPassword
$apiPasswordText=ConvertTo-BootstrapPasswordText -Secure $ApiPassword
$workerPasswordText=ConvertTo-BootstrapPasswordText -Secure $WorkerPassword
$connectionArguments=@("-X","-q","-t","-A","-v","ON_ERROR_STOP=1","--host=$PgHost","--port=$PgPort","--username=$superuser","--dbname=postgres","-f","-")
$allRoles=@($superuser,$AdminUser,$SchemaOwnerRole,$MigrationRole,$ApiRole,$WorkerRole)|Select-Object -Unique
$rolesInClause=(@($allRoles|ForEach-Object{ConvertTo-SqlStringLiteral $_}) -join ",")
$expectedLogin=@{}
$expectedLogin[$superuser]=$true
$expectedLogin[$AdminUser]=$true
$expectedLogin[$SchemaOwnerRole]=$false
$expectedLogin[$MigrationRole]=$true
$expectedLogin[$ApiRole]=$true
$expectedLogin[$WorkerRole]=$true
# Booleans concatenated into text render as 'true'/'false' (boolean::text),
# while the parser expects PostgreSQL's single-character boolean display.
# Cast explicitly through left(...::text,1) so every flag arrives as 't'/'f'.
$detectSql="SELECT rolname||'|'||left(rolcanlogin::text,1)||'|'||left(rolsuper::text,1)||'|'||left(rolcreaterole::text,1)||'|'||left(rolcreatedb::text,1)||'|'||left(rolbypassrls::text,1)||'|'||left(rolreplication::text,1) FROM pg_roles WHERE rolname IN ($rolesInClause) ORDER BY rolname;"
 $detectOutput=Invoke-BootstrapPsql -PsqlPath $psql -ConnectionPassword $adminPasswordText -Arguments $connectionArguments -Sql $detectSql -Stage "detect"
 $knownRoles=@{}
 foreach($line in @($detectOutput -split "\r?\n")){
  if([string]::IsNullOrWhiteSpace($line)){continue}
  $fields=$line.Split("|")
  if($fields.Count -ne 7){throw "PostgreSQL bootstrap role detection returned an unexpected result."}
  $knownRoles[$fields[0]]=@{login=($fields[1] -ceq "t");super=($fields[2] -ceq "t");createrole=($fields[3] -ceq "t");createdb=($fields[4] -ceq "t");bypassrls=($fields[5] -ceq "t");replication=($fields[6] -ceq "t")}
 }
 if(-not $knownRoles.ContainsKey($superuser) -or -not $knownRoles[$superuser].super){
  # Detected rows contain only role names and boolean flags - never secret
  # material - so they are safe to surface for fail-closed diagnosis.
  throw "PostgreSQL cluster superuser was not created by the expected initialization; refusing database bootstrap. detected roles: [$detectOutput]"
 }
 $dbSql="SELECT datname||'|'||pg_get_userbyid(datdba) FROM pg_database WHERE datname = "+(ConvertTo-SqlStringLiteral $DatabaseName)+";"
 $dbOutput=Invoke-BootstrapPsql -PsqlPath $psql -ConnectionPassword $adminPasswordText -Arguments $connectionArguments -Sql $dbSql -Stage "detect-database"
 $dbLines=@($dbOutput -split "\r?\n"|Where-Object{-not [string]::IsNullOrWhiteSpace($_)})
 $databaseExists=$dbLines.Count -gt 0
 $databaseOwner=$null
 if($databaseExists){
  if($dbLines.Count -ne 1){throw "PostgreSQL bootstrap database detection returned an unexpected result."}
  $dbFields=$dbLines[0].Split("|")
  if($dbFields.Count -ne 2){throw "PostgreSQL bootstrap database detection returned an unexpected result."}
  $databaseOwner=$dbFields[1]
  if($databaseOwner -cne $SchemaOwnerRole){throw "Existing database does not match the expected owner; refusing to adopt it."}
 }

 # Fail closed on any pre-existing role whose attributes do not match the
 # bootstrap definition; a privileged or login-mismatched role is foreign.
 $managedRoles=@($AdminUser,$SchemaOwnerRole,$MigrationRole,$ApiRole,$WorkerRole)|Select-Object -Unique
 foreach($role in $managedRoles){
  if($role -ceq $superuser){continue}
  if($knownRoles.ContainsKey($role)){
   $info=$knownRoles[$role]
   if($info.super -or $info.createrole -or $info.createdb -or $info.bypassrls -or $info.replication){throw "Existing PostgreSQL role does not match the expected bootstrap definition; refusing to adopt it."}
   if($info.login -ne $expectedLogin[$role]){throw "Existing PostgreSQL role does not match the expected bootstrap definition; refusing to adopt it."}
  }
 }

 # Existing login roles are never password-reset during a retry. Prove that
 # each supplied credential already authenticates before any mutation; a
 # mismatch aborts without rotating credentials or partially converging state.
 $existingCredentials=@(
  [pscustomobject]@{Role=$AdminUser;Password=$adminPasswordText},
  [pscustomobject]@{Role=$MigrationRole;Password=$migrationPasswordText},
  [pscustomobject]@{Role=$ApiRole;Password=$apiPasswordText},
  [pscustomobject]@{Role=$WorkerRole;Password=$workerPasswordText}
 )
 $rolesConverged=[Collections.Generic.List[string]]::new()
 foreach($credential in $existingCredentials){
  if($credential.Role -ceq $superuser -or -not $knownRoles.ContainsKey($credential.Role)){continue}
  $loginArguments=@("-X","-q","-t","-A","-v","ON_ERROR_STOP=1","--host=$PgHost","--port=$PgPort","--username=$($credential.Role)","--dbname=postgres","-f","-")
  try{
   $loginOutput=Invoke-BootstrapPsql -PsqlPath $psql -ConnectionPassword $credential.Password -Arguments $loginArguments -Sql "SELECT current_user;" -Stage "verify-existing-credential"
   if($loginOutput.Trim() -cne $credential.Role){throw "credential-mismatch"}
  }catch{
   throw "Existing PostgreSQL login credential verification failed for role '$($credential.Role)'; refusing to rotate or overwrite its password."
  }
  $rolesConverged.Add($credential.Role)
 }

 # Never adopt a pre-existing membership that lets the migration login
 # administer role grants. The intended contract permits SET only.
 $membershipPreflightSql="SELECT left(admin_option::text,1) FROM pg_auth_members m JOIN pg_roles member ON member.oid=m.member JOIN pg_roles granted ON granted.oid=m.roleid WHERE member.rolname="+(ConvertTo-SqlStringLiteral $MigrationRole)+" AND granted.rolname="+(ConvertTo-SqlStringLiteral $SchemaOwnerRole)+";"
 $membershipPreflight=Invoke-BootstrapPsql -PsqlPath $psql -ConnectionPassword $adminPasswordText -Arguments $connectionArguments -Sql $membershipPreflightSql -Stage "preflight-migration-membership"
 if($membershipPreflight.Trim() -ceq "t"){throw "Existing migration role membership has ADMIN OPTION; refusing to adopt it."}
 $statements=[Collections.Generic.List[string]]::new()
 $rolesCreated=[Collections.Generic.List[string]]::new()
 if($AdminUser -cne $superuser){
  if(-not $knownRoles.ContainsKey($AdminUser)){$statements.Add("CREATE ROLE "+$AdminUser+" LOGIN PASSWORD "+(ConvertTo-SqlStringLiteral $adminPasswordText)+";");$rolesCreated.Add($AdminUser)}
 }
 if(-not $knownRoles.ContainsKey($SchemaOwnerRole)){$statements.Add("CREATE ROLE "+$SchemaOwnerRole+";");$rolesCreated.Add($SchemaOwnerRole)}
 if(-not $knownRoles.ContainsKey($MigrationRole)){$statements.Add("CREATE ROLE "+$MigrationRole+" LOGIN PASSWORD "+(ConvertTo-SqlStringLiteral $migrationPasswordText)+";");$rolesCreated.Add($MigrationRole)}
 if(-not $knownRoles.ContainsKey($ApiRole)){$statements.Add("CREATE ROLE "+$ApiRole+" LOGIN PASSWORD "+(ConvertTo-SqlStringLiteral $apiPasswordText)+";");$rolesCreated.Add($ApiRole)}
 if(-not $knownRoles.ContainsKey($WorkerRole)){$statements.Add("CREATE ROLE "+$WorkerRole+" LOGIN PASSWORD "+(ConvertTo-SqlStringLiteral $workerPasswordText)+";");$rolesCreated.Add($WorkerRole)}
 $databaseCreated=$false
 if(-not $databaseExists){$statements.Add("CREATE DATABASE "+$DatabaseName+" OWNER "+$SchemaOwnerRole+";");$databaseCreated=$true}
 $statements.Add("GRANT ALL ON DATABASE "+$DatabaseName+" TO "+$MigrationRole+";")
 # The disposable PostgreSQL 18 / Prisma 7.10.1 experiment proved this exact
 # role-default mechanism: the login authenticates as MigrationRole while
 # every migration connection executes with SchemaOwnerRole as current_user.
 $statements.Add("GRANT "+$SchemaOwnerRole+" TO "+$MigrationRole+" WITH INHERIT FALSE, SET TRUE;")
 $statements.Add("ALTER ROLE "+$MigrationRole+" SET role = "+(ConvertTo-SqlStringLiteral $SchemaOwnerRole)+";")
 if($AdminUser -cne $superuser){$statements.Add("GRANT ALL ON DATABASE "+$DatabaseName+" TO "+$AdminUser+";")}
 $mutateSql=($statements -join [Environment]::NewLine)
 if(-not [string]::IsNullOrWhiteSpace($mutateSql)){Invoke-BootstrapPsql -PsqlPath $psql -ConnectionPassword $adminPasswordText -Arguments $connectionArguments -Sql $mutateSql -Stage "mutate"|Out-Null}

 # Verify the converged state with a fresh read before reporting success.
 $verifyOutput=Invoke-BootstrapPsql -PsqlPath $psql -ConnectionPassword $adminPasswordText -Arguments $connectionArguments -Sql $detectSql -Stage "verify-roles"
 $verifiedRoles=@{}
 foreach($line in @($verifyOutput -split "\r?\n")){
  if([string]::IsNullOrWhiteSpace($line)){continue}
  $fields=$line.Split("|")
  if($fields.Count -ne 7){throw "PostgreSQL bootstrap verification returned an unexpected result."}
  $verifiedRoles[$fields[0]]=@{login=($fields[1] -ceq "t");super=($fields[2] -ceq "t");createrole=($fields[3] -ceq "t");createdb=($fields[4] -ceq "t");bypassrls=($fields[5] -ceq "t");replication=($fields[6] -ceq "t")}
 }
 $verifyRoleList=@($superuser)+@($managedRoles)
 foreach($role in @($verifyRoleList|Select-Object -Unique)){
  if(-not $verifiedRoles.ContainsKey($role)){throw "PostgreSQL bootstrap verification found a missing role; refusing to report success."}
  $info=$verifiedRoles[$role]
  if($role -eq $superuser){if(-not $info.super){throw "PostgreSQL bootstrap verification found an unexpected superuser state; refusing to report success."};continue}
  if($info.super -or $info.createrole -or $info.createdb -or $info.bypassrls -or $info.replication -or ($info.login -ne $expectedLogin[$role])){throw "PostgreSQL bootstrap verification found an unexpected role state; refusing to report success."}
 }
 $verifyDbOutput=Invoke-BootstrapPsql -PsqlPath $psql -ConnectionPassword $adminPasswordText -Arguments $connectionArguments -Sql $dbSql -Stage "verify-database"
 $verifyDbLines=@($verifyDbOutput -split "\r?\n"|Where-Object{-not [string]::IsNullOrWhiteSpace($_)})
 if($verifyDbLines.Count -ne 1){throw "PostgreSQL bootstrap verification found a missing database; refusing to report success."}
 $verifyDbFields=$verifyDbLines[0].Split("|")
 if($verifyDbFields.Count -ne 2 -or $verifyDbFields[1] -cne $SchemaOwnerRole){throw "PostgreSQL bootstrap verification found an unexpected database owner; refusing to report success."}
 # Verify both the explicit SET-only membership and the role default that
 # Prisma uses on each new connection. Never report bootstrap success unless
 # the effective migration identity can be established by the real login.
 $membershipSql="SELECT member.rolname||'|'||granted.rolname||'|'||left(m.inherit_option::text,1)||'|'||left(m.set_option::text,1) FROM pg_auth_members m JOIN pg_roles member ON member.oid=m.member JOIN pg_roles granted ON granted.oid=m.roleid WHERE member.rolname="+(ConvertTo-SqlStringLiteral $MigrationRole)+" AND granted.rolname="+(ConvertTo-SqlStringLiteral $SchemaOwnerRole)+";"
 $membershipOutput=Invoke-BootstrapPsql -PsqlPath $psql -ConnectionPassword $adminPasswordText -Arguments $connectionArguments -Sql $membershipSql -Stage "verify-migration-membership"
 if($membershipOutput.Trim() -cne ($MigrationRole+"|"+$SchemaOwnerRole+"|f|t")){throw "PostgreSQL bootstrap verification found an unexpected migration role membership; refusing to report success."}
 $settingSql="SELECT count(*) FROM pg_db_role_setting s JOIN pg_roles r ON r.oid=s.setrole WHERE r.rolname="+(ConvertTo-SqlStringLiteral $MigrationRole)+" AND s.setdatabase=0 AND "+(ConvertTo-SqlStringLiteral ("role="+$SchemaOwnerRole))+"=ANY(s.setconfig);"
 $settingOutput=Invoke-BootstrapPsql -PsqlPath $psql -ConnectionPassword $adminPasswordText -Arguments $connectionArguments -Sql $settingSql -Stage "verify-migration-role-setting"
 if($settingOutput.Trim() -cne "1"){throw "PostgreSQL bootstrap verification found an unexpected migration role default; refusing to report success."}
 # Password texts remain referenced only until script exit; they are never
 # written to disk, argv, logs or exception messages.
 [pscustomobject]@{status="ok";database=$DatabaseName;databaseCreated=$databaseCreated;rolesCreated=@($rolesCreated);rolesConverged=@($rolesConverged);credentialTransport="child-environment-and-stdin";mutated=$true}|ConvertTo-Json -Depth 4
