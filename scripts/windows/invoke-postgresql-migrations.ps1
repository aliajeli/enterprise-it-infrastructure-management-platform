[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
 [Parameter(Mandatory=$true)][string]$InstallRoot,
 [Parameter(Mandatory=$true)][string]$PgHost,
 [Parameter(Mandatory=$true)][int]$PgPort,
 [Parameter(Mandatory=$true)][string]$DatabaseName,
 [Parameter(Mandatory=$true)][string]$MigrationRole,
 [Parameter(Mandatory=$true)][Security.SecureString]$MigrationPassword,
 [Parameter(Mandatory=$true)][string]$SchemaOwnerRole,
 [Parameter(Mandatory=$true)][string]$ApiRole,
 [Parameter(Mandatory=$true)][string]$WorkerRole,
 [Parameter(Mandatory=$true)][Security.SecureString]$AdminPassword,
 [Parameter(Mandatory=$true)][string]$AdminUser
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function ConvertTo-PlainText([Security.SecureString]$Secure){$ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}}
function Assert-SafeIdentifier([string]$Name,[string]$Label){if($Name -notmatch '^[A-Za-z][A-Za-z0-9_]{0,62}$'){throw "Unsafe SQL identifier for ${Label}."}}
foreach($pair in @(@($DatabaseName,"DatabaseName"),@($MigrationRole,"MigrationRole"),@($SchemaOwnerRole,"SchemaOwnerRole"),@($ApiRole,"ApiRole"),@($WorkerRole,"WorkerRole"),@($AdminUser,"AdminUser"))){Assert-SafeIdentifier -Name $pair[0] -Label $pair[1]}
if($WhatIfPreference){[pscustomobject]@{status="whatif";database=$DatabaseName;mutated=$false}|ConvertTo-Json -Depth 4;return}
if(-not $PSCmdlet.ShouldProcess($DatabaseName,"Apply Prisma migrations with controlled migration identity")){return}

$root=[IO.Path]::GetFullPath($InstallRoot)
$prismaConfig=Join-Path $root "packages\database\prisma.config.ts"
$schemaPath=Join-Path $root "packages\database\prisma\schema.prisma"
if(-not(Test-Path -LiteralPath $schemaPath -PathType Leaf)){throw "Prisma schema is missing from staged payload."}

$migrationPass=ConvertTo-PlainText $MigrationPassword
$adminPass=ConvertTo-PlainText $AdminPassword
try{
 # Build DATABASE_URL for migration role. Password is URL-encoded; process-scoped env only.
 $encodedPass=[Uri]::EscapeDataString($migrationPass)
 $migrationUrl="postgresql://${MigrationRole}:${encodedPass}@${PgHost}:${PgPort}/${DatabaseName}?schema=public"

 $psi=[Diagnostics.ProcessStartInfo]::new()
 # Prefer npx in staged runtime; fall back to npm exec. No shell.
 $nodeExe=Join-Path $root "runtime\node.exe"
 $npmCmd=Join-Path $root "runtime\npm.cmd"
 $npxCmd=Join-Path $root "runtime\npx.cmd"
 if(Test-Path -LiteralPath $npxCmd -PathType Leaf){$psi.FileName=$npxCmd; $psi.ArgumentList.Add("prisma"); $psi.ArgumentList.Add("migrate"); $psi.ArgumentList.Add("deploy"); $psi.ArgumentList.Add("--config"); $psi.ArgumentList.Add($prismaConfig)}
 elseif(Test-Path -LiteralPath $npmCmd -PathType Leaf){$psi.FileName=$npmCmd; $psi.ArgumentList.Add("run"); $psi.ArgumentList.Add("db:migrate:deploy"); $psi.ArgumentList.Add("--workspace"); $psi.ArgumentList.Add("@platform/database")}
 else{throw "No staged npm/npx runtime found for Prisma migration."}
 $psi.WorkingDirectory=$root
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.RedirectStandardInput=$false
 $psi.Environment["DATABASE_URL"]=$migrationUrl
 $psi.Environment["PGHOST"]=$PgHost
 $psi.Environment["PGPORT"]=[string]$PgPort
 $psi.Environment["PGDATABASE"]=$DatabaseName
 $p=[Diagnostics.Process]::Start($psi)
 $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync();$p.WaitForExit()
 $out=$outTask.GetAwaiter().GetResult();$err=$errTask.GetAwaiter().GetResult()
 if($p.ExitCode -ne 0){throw "Prisma migration failed. Dependent services must not start. Exit=$($p.ExitCode)."}

 # Verify migration identity/ownership expectations and reapply runtime grants.
 $psqlPsi=[Diagnostics.ProcessStartInfo]::new()
 $psqlPsi.FileName="psql"
 foreach($a in @("--no-psqlrc","-v","ON_ERROR_STOP=1","-h",$PgHost,"-p",[string]$PgPort,"-U",$AdminUser,"-d",$DatabaseName,"-c",
"DO $$ BEGIN END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, \"$ApiRole\", \"$WorkerRole\";
GRANT USAGE ON SCHEMA public TO \"$ApiRole\", \"$WorkerRole\";
GRANT SELECT,INSERT,UPDATE ON TABLE public.users,public.sessions,public.branches,public.user_branch_access,public.assets,public.switch_profiles,public.switch_ports,public.discovery_runs TO \"$ApiRole\";
GRANT INSERT ON TABLE public.audit_events TO \"$ApiRole\";
GRANT SELECT,INSERT ON TABLE public.port_observations TO \"$ApiRole\";
GRANT SELECT,UPDATE ON TABLE public.discovery_runs TO \"$WorkerRole\";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"$ApiRole\";
")){$psqlPsi.ArgumentList.Add($a)}
 $psqlPsi.UseShellExecute=$false;$psqlPsi.CreateNoWindow=$true;$psqlPsi.RedirectStandardOutput=$true;$psqlPsi.RedirectStandardError=$true
 $psqlPsi.Environment["PGPASSWORD"]=$adminPass
 $pp=[Diagnostics.Process]::Start($psqlPsi)
 $ppOut=$pp.StandardOutput.ReadToEndAsync();$ppErr=$pp.StandardError.ReadToEndAsync();$pp.WaitForExit()
 $null=$ppOut.GetAwaiter().GetResult();$null=$ppErr.GetAwaiter().GetResult()
 if($pp.ExitCode -ne 0){throw "Post-migration grant verification/reapplication failed."}

 [pscustomobject]@{status="ok";database=$DatabaseName;migrationRole=$MigrationRole;schemaOwner=$SchemaOwnerRole;mutated=$true} | ConvertTo-Json -Depth 4
}finally{
 $migrationPass=$null;$adminPass=$null
}
