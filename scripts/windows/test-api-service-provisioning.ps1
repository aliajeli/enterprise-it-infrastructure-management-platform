$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "provision-api-service.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$plan=Get-ApiServiceProvisioningPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
if($plan.ServiceName -ne "EnterpriseITApi"){throw "Unexpected service name."}
if($plan.ServiceAccount -ne "NT SERVICE\EnterpriseITApi"){throw "Unexpected service identity."}
if($plan.ServiceSidType -ne "unrestricted"){throw "Service SID must be unrestricted."}
if($plan.RecoveryResetSeconds -ne 86400 -or $plan.RecoveryActions -ne 'restart/60000/restart/300000/""/0'){throw "Unexpected SCM recovery policy."}
if($plan.StartService){throw "Provisioning must not start the API before DB/configuration readiness."}\nif($plan.DatabaseConfigPath -notlike "*EnterpriseIT\\Api\\database.config.dpapi"){throw "API config path is not under ProgramData."}
$invalid=@((Join-Path $env:TEMP "EnterpriseIT\1.2.3"),(Join-Path $pf "EnterpriseIT\current"),(Join-Path $pf "OtherProduct\1.2.3"),(Join-Path $pf "EnterpriseIT\1.2.3\Nested"))
foreach($root in $invalid){$rejected=$false;try{Get-ApiServiceProvisioningPlan -InstallRoot $root|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Unsafe install root accepted: $root"}}
Write-Host "API service provisioning policy tests passed."

$dryPlan=[pscustomobject]@{
    ServiceName="EnterpriseITApi";ServiceAccount="NT SERVICE\EnterpriseITApi";ServiceSidType="unrestricted"
    InstallRoot=(Join-Path $pf "EnterpriseIT\1.2.3")
    ServiceHostPath=(Join-Path $pf "EnterpriseIT\1.2.3\EnterpriseIT.ApiServiceHost.exe")
    NodePath=(Join-Path $pf "EnterpriseIT\1.2.3\runtime\node.exe")
    ApiEntryPoint=(Join-Path $pf "EnterpriseIT\1.2.3\apps\api\dist\server.js")
    RecoveryResetSeconds=86400;RecoveryActions='restart/60000/restart/300000/""/0';StartService=$false
}
$dryResult=Invoke-ApiServiceProvisioning -Plan $dryPlan -WhatIf
if(-not $dryResult.dryRun){throw "WhatIf must return an explicit dry-run result."}
if($dryResult.serviceStarted){throw "WhatIf must never start the API service."}
