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
# Validation is shared with the bootstrap entry point and does not contact the
# server. It is not cluster identity or ownership verification.
. (Join-Path $PSScriptRoot 'postgresql-deployment-inputs.ps1')
Assert-PostgreSqlDeploymentInputs -PgHost $PgHost -PgPort $PgPort -DatabaseName $DatabaseName -AdminUser $AdminUser -SchemaOwnerRole $SchemaOwnerRole -MigrationRole $MigrationRole -ApiRole $ApiRole -WorkerRole $WorkerRole

if($WhatIfPreference){[pscustomobject]@{status="whatif";database=$DatabaseName;mutated=$false}|ConvertTo-Json -Depth 4;return}
# Fail closed until the bootstrap credential channel and ownership/adoption
# checks are reviewed and tested. Never place passwords in SQL argv or logs.
throw "PostgreSQL bootstrap and migration are disabled pending secure credential transport and ownership verification."
