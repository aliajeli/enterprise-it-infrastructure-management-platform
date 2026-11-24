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

function Assert-SafeIdentifier([string]$Name,[string]$Label){
 if($Name -notmatch '^[A-Za-z][A-Za-z0-9_]{0,62}$'){throw "Unsafe SQL identifier for ${Label}."}
}
foreach($pair in @(@($DatabaseName,"DatabaseName"),@($SchemaOwnerRole,"SchemaOwnerRole"),@($MigrationRole,"MigrationRole"),@($ApiRole,"ApiRole"),@($WorkerRole,"WorkerRole"))){
 Assert-SafeIdentifier -Name $pair[0] -Label $pair[1]
}
if($PgPort -lt 1 -or $PgPort -gt 65535){throw "Invalid PostgreSQL port."}

if($WhatIfPreference){
 [pscustomobject]@{status="whatif";database=$DatabaseName;schemaOwner=$SchemaOwnerRole;migrationRole=$MigrationRole;apiRole=$ApiRole;workerRole=$WorkerRole;mutated=$false} | ConvertTo-Json -Depth 4
 return
}
# Fail closed until the bootstrap credential channel and ownership/adoption
# checks are reviewed and tested. Never place passwords in SQL argv or logs.
throw "PostgreSQL bootstrap and migration are disabled pending secure credential transport and ownership verification."
