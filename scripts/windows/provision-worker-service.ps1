[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param([Parameter(Mandatory=$true)][string]$InstallRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Get-WorkerServiceProvisioningPlan {
 param([Parameter(Mandatory=$true)][string]$InstallRoot)
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
 if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be Program Files\EnterpriseIT\<major.minor.patch>."}
 [pscustomobject]@{ServiceName="EnterpriseITWorker";ServiceAccount="NT SERVICE\EnterpriseITWorker";ServiceSidType="unrestricted";InstallRoot=$root;ServiceHostPath=(Join-Path $root "EnterpriseIT.WorkerServiceHost.exe");NodePath=(Join-Path $root "runtime\node.exe");WorkerEntryPoint=(Join-Path $root "apps\worker\dist\main.js");RecoveryResetSeconds=86400;RecoveryActions='restart/60000/restart/300000/""/0';StartService=$false}
}
function Invoke-WorkerSc([string[]]$Arguments){& sc.exe @Arguments|Out-Null;if($LASTEXITCODE -ne 0){throw "Worker SCM provisioning failed with exit code $LASTEXITCODE."}}
function Invoke-WorkerServiceProvisioning {
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
 param([Parameter(Mandatory=$true)][pscustomobject]$Plan)
 if($WhatIfPreference){return [pscustomobject]@{serviceName=$Plan.ServiceName;serviceAccount=$Plan.ServiceAccount;serviceSidType=$Plan.ServiceSidType;installRoot=$Plan.InstallRoot;dryRun=$true;serviceStarted=$false}}
 foreach($file in @($Plan.ServiceHostPath,$Plan.NodePath,$Plan.WorkerEntryPoint)){if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Required immutable Worker payload file is missing."}}
 $service=Get-CimInstance Win32_Service -Filter "Name='EnterpriseITWorker'" -ErrorAction SilentlyContinue
 if($null -eq $service){if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Create dedicated virtual-account Worker service")){Invoke-WorkerSc @("create",$Plan.ServiceName,"binPath=",('"'+$Plan.ServiceHostPath+'"'),"obj=",$Plan.ServiceAccount,"start=","auto","DisplayName=","Enterprise IT Worker")}}
 elseif($service.PathName -notlike "*$($Plan.ServiceHostPath)*" -or $service.StartName -ine $Plan.ServiceAccount){throw "Existing Worker service path or logon identity differs; refusing to replace it."}
 if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Configure service SID and bounded SCM recovery")){Invoke-WorkerSc @("sidtype",$Plan.ServiceName,"unrestricted");Invoke-WorkerSc @("failure",$Plan.ServiceName,"reset=",[string]$Plan.RecoveryResetSeconds,"actions=",$Plan.RecoveryActions);Invoke-WorkerSc @("failureflag",$Plan.ServiceName,"1")}
 $sidOutput=(& sc.exe showsid $Plan.ServiceName 2>&1|Out-String);if($LASTEXITCODE -ne 0){throw "Could not resolve Worker service SID."}
 $m=[regex]::Match($sidOutput,"S-1-5-80-(?:\d+-){4}\d+");if(-not $m.Success){throw "SCM returned an invalid Worker service SID."};$sid=$m.Value
 if($PSCmdlet.ShouldProcess($Plan.InstallRoot,"Apply immutable Program Files ACL")){& icacls.exe $Plan.InstallRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)") /T|Out-Host;if($LASTEXITCODE -ne 0){throw "Could not apply Worker installation ACL."}}
 $sidConfig=(& sc.exe qsidtype $Plan.ServiceName 2>&1|Out-String);if($LASTEXITCODE -ne 0 -or $sidConfig -notmatch "UNRESTRICTED"){throw "Worker service SID is not UNRESTRICTED."}
 [pscustomobject]@{serviceName=$Plan.ServiceName;serviceAccount=$Plan.ServiceAccount;serviceSid=$sid;serviceSidType=$Plan.ServiceSidType;installRoot=$Plan.InstallRoot;recoveryPolicyConfigured=$true;installAclConfigured=$true;serviceStarted=$false}
}
if($MyInvocation.InvocationName -ne "."){$plan=Get-WorkerServiceProvisioningPlan -InstallRoot $InstallRoot;Invoke-WorkerServiceProvisioning -Plan $plan|ConvertTo-Json -Depth 4}
