$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "provision-web-service.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$plan=Get-WebServiceProvisioningPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
if($plan.ServiceName -ne "EnterpriseITWeb" -or $plan.ServiceAccount -ne "NT SERVICE\EnterpriseITWeb" -or $plan.ServiceSidType -ne "unrestricted"){throw "Unexpected Web service identity."}
if($plan.StartService){throw "Provisioning must not start Web before dependencies are ready."}
$invalid=@((Join-Path $env:TEMP "EnterpriseIT\1.2.3"),(Join-Path $pf "EnterpriseIT\current"),(Join-Path $pf "OtherProduct\1.2.3"),(Join-Path $pf "EnterpriseIT\1.2.3\Nested"))
foreach($root in $invalid){$rejected=$false;try{Get-WebServiceProvisioningPlan -InstallRoot $root|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Unsafe install root accepted: $root"}}
$dry=[pscustomobject]@{ServiceName="EnterpriseITWeb";ServiceAccount="NT SERVICE\EnterpriseITWeb";ServiceSidType="unrestricted";InstallRoot=(Join-Path $pf "EnterpriseIT\1.2.3");ServiceHostPath=(Join-Path $pf "EnterpriseIT\1.2.3\EnterpriseIT.WebServiceHost.exe");NodePath=(Join-Path $pf "EnterpriseIT\1.2.3\runtime\node.exe");WebEntryPoint=(Join-Path $pf "EnterpriseIT\1.2.3\apps\web\.next\standalone\service-entry.cjs");RecoveryResetSeconds=86400;RecoveryActions='restart/60000/restart/300000/""/0';StartService=$false}
$result=Invoke-WebServiceProvisioning -Plan $dry -WhatIf
if(-not $result.dryRun -or $result.serviceStarted){throw "WhatIf must be side-effect free and must not start Web."}
Write-Host "Web service provisioning policy tests passed."
