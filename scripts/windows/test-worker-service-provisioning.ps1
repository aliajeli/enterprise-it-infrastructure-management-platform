$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "provision-worker-service.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$plan=Get-WorkerServiceProvisioningPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
if($plan.ServiceName -ne "EnterpriseITWorker" -or $plan.ServiceAccount -ne "NT SERVICE\EnterpriseITWorker" -or $plan.ServiceSidType -ne "unrestricted"){throw "Unexpected Worker service identity."}
if($plan.StartService){throw "Provisioning must not start Worker before dependencies are ready."}
if($plan.DatabaseConfigPath -notlike "*EnterpriseIT\\Worker\\database.config.dpapi"){throw "Worker config path is not under ProgramData."}
$invalid=@((Join-Path $env:TEMP "EnterpriseIT\1.2.3"),(Join-Path $pf "EnterpriseIT\current"),(Join-Path $pf "OtherProduct\1.2.3"),(Join-Path $pf "EnterpriseIT\1.2.3\Nested"))
foreach($root in $invalid){$rejected=$false;try{Get-WorkerServiceProvisioningPlan -InstallRoot $root|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Unsafe install root accepted: $root"}}
$dry=[pscustomobject]@{ServiceName="EnterpriseITWorker";ServiceAccount="NT SERVICE\EnterpriseITWorker";ServiceSidType="unrestricted";InstallRoot=(Join-Path $pf "EnterpriseIT\1.2.3");ServiceHostPath=(Join-Path $pf "EnterpriseIT\1.2.3\EnterpriseIT.WorkerServiceHost.exe");NodePath=(Join-Path $pf "EnterpriseIT\1.2.3\runtime\node.exe");WorkerEntryPoint=(Join-Path $pf "EnterpriseIT\1.2.3\apps\worker\dist\main.js");RecoveryResetSeconds=86400;RecoveryActions='restart/60000/restart/300000/""/0';StartService=$false}
$result=Invoke-WorkerServiceProvisioning -Plan $dry -WhatIf
if(-not $result.dryRun -or $result.serviceStarted){throw "WhatIf must be side-effect free and must not start Worker."}
Write-Host "Worker service provisioning policy tests passed."
