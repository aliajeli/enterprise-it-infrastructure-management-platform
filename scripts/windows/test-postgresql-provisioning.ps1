$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "provision-postgresql-service.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$p=Get-PostgreSqlServiceProvisioningPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -DataRoot (Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")
if($p.ServiceName -ne "EnterpriseITPostgreSQL" -or $p.ServiceAccount -ne "NT SERVICE\EnterpriseITPostgreSQL" -or $p.ListenAddress -ne "127.0.0.1" -or $p.Port -ne 5432 -or $p.StartService){throw "Unexpected PostgreSQL service plan."}
$bad=@((Join-Path $pf "EnterpriseIT\current"),(Join-Path $env:TEMP "EnterpriseIT\PostgreSQL\18\data"),(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\17\data"))
foreach($x in $bad){$rejected=$false;try{Get-PostgreSqlServiceProvisioningPlan -InstallRoot $x -DataRoot (Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Unsafe PostgreSQL path accepted."}}
$r=Invoke-PostgreSqlServiceProvisioning -Plan ([pscustomobject]@{ServiceName="EnterpriseITPostgreSQL";ServiceAccount="NT SERVICE\EnterpriseITPostgreSQL";InstallRoot=(Join-Path $pf "EnterpriseIT\1.2.3");DataRoot=(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")}) -WhatIf
if(-not $r.dryRun -or $r.serviceStarted){throw "PostgreSQL WhatIf must be side-effect free."}
Write-Host "PostgreSQL provisioning policy tests passed."
