# Shared read-only input validation for the currently disabled PostgreSQL
# bootstrap and migration entry points. No connection or mutation occurs here.
function Assert-PostgreSqlDeploymentInputs {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory=$true)][string]$PgHost,
  [Parameter(Mandatory=$true)][int]$PgPort,
  [Parameter(Mandatory=$true)][string]$DatabaseName,
  [Parameter(Mandatory=$true)][string]$AdminUser,
  [Parameter(Mandatory=$true)][string]$SchemaOwnerRole,
  [Parameter(Mandatory=$true)][string]$MigrationRole,
  [Parameter(Mandatory=$true)][string]$ApiRole,
  [Parameter(Mandatory=$true)][string]$WorkerRole
 )
 # A host name can resolve elsewhere or be rebound. Only the explicitly
 # expected IPv4 loopback target is currently supported for first installation.
 if($PgHost -cne '127.0.0.1' -or $PgPort -lt 1 -or $PgPort -gt 65535){throw 'Invalid PostgreSQL deployment endpoint.'}
 $names=@($DatabaseName,$AdminUser,$SchemaOwnerRole,$MigrationRole,$ApiRole,$WorkerRole)
 foreach($name in $names){
  # ASCII lower-case only: avoids PostgreSQL folding/quoting ambiguities and
  # keeps the 63-byte PostgreSQL identifier limit equal to character count.
  if($name -cnotmatch '^[a-z][a-z0-9_]{0,62}$' -or $name.StartsWith('pg_',[StringComparison]::Ordinal)){
   throw 'Invalid or reserved PostgreSQL deployment identifier.'
  }
 }
 if($DatabaseName -cin @('postgres','template0','template1')){throw 'Reserved PostgreSQL database name.'}
 $roles=@($AdminUser,$SchemaOwnerRole,$MigrationRole,$ApiRole,$WorkerRole)
 $roleSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($role in $roles){
  if(-not $roleSet.Add($role)){throw 'PostgreSQL deployment roles must be distinct.'}
 }
 foreach($role in @($SchemaOwnerRole,$MigrationRole,$ApiRole,$WorkerRole)){
  if($role -cin @('postgres','public')){throw 'Reserved PostgreSQL deployment role.'}
 }
 if($AdminUser -ceq 'public'){throw 'Reserved PostgreSQL administrator role.'}
}
