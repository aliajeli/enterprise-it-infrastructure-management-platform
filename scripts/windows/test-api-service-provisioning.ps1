$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "provision-api-service.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$plan=Get-ApiServiceProvisioningPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
if($plan.ServiceName -ne "EnterpriseITApi"){throw "Unexpected service name."}
if($plan.ServiceAccount -ne "NT SERVICE\EnterpriseITApi"){throw "Unexpected service identity."}
if($plan.ServiceSidType -ne "unrestricted"){throw "Service SID must be unrestricted."}
if($plan.RecoveryResetSeconds -ne 86400 -or $plan.RecoveryActions -ne 'restart/60000/restart/300000/""/0'){throw "Unexpected SCM recovery policy."}
if($plan.StartService){throw "Provisioning must not start the API before DB/configuration readiness."}
$invalid=@((Join-Path $env:TEMP "EnterpriseIT\1.2.3"),(Join-Path $pf "EnterpriseIT\current"),(Join-Path $pf "OtherProduct\1.2.3"),(Join-Path $pf "EnterpriseIT\1.2.3\Nested"))
foreach($root in $invalid){$rejected=$false;try{Get-ApiServiceProvisioningPlan -InstallRoot $root|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Unsafe install root accepted: $root"}}
Write-Host "API service provisioning policy tests passed."
