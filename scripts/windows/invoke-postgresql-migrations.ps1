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
function Assert-SafeIdentifier([string]$Name,[string]$Label){if($Name -notmatch '^[A-Za-z][A-Za-z0-9_]{0,62}$'){throw "Unsafe SQL identifier for ${Label}."}}
foreach($pair in @(@($DatabaseName,"DatabaseName"),@($MigrationRole,"MigrationRole"),@($SchemaOwnerRole,"SchemaOwnerRole"),@($ApiRole,"ApiRole"),@($WorkerRole,"WorkerRole"),@($AdminUser,"AdminUser"))){Assert-SafeIdentifier -Name $pair[0] -Label $pair[1]}
if($WhatIfPreference){[pscustomobject]@{status="whatif";database=$DatabaseName;mutated=$false}|ConvertTo-Json -Depth 4;return}
# Fail closed until the bootstrap credential channel and ownership/adoption
# checks are reviewed and tested. Never place passwords in SQL argv or logs.
throw "PostgreSQL bootstrap and migration are disabled pending secure credential transport and ownership verification."
