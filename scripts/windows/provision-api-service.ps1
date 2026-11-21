[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param([Parameter(Mandatory=$true)][string]$InstallRoot,[Security.SecureString]$DatabaseUrl)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Get-ApiServiceProvisioningPlan {
 param([Parameter(Mandatory=$true)][string]$InstallRoot)
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
 if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be Program Files\EnterpriseIT\<major.minor.patch>."}
 [pscustomobject]@{ServiceName="EnterpriseITApi";ServiceAccount="NT SERVICE\EnterpriseITApi";ServiceSidType="unrestricted";InstallRoot=$root;ServiceHostPath=(Join-Path $root "EnterpriseIT.ApiServiceHost.exe");NodePath=(Join-Path $root "runtime\node.exe");ApiEntryPoint=(Join-Path $root "apps\api\dist\server.js");DatabaseConfigRoot=(Join-Path $env:ProgramData "EnterpriseIT\Api");DatabaseConfigPath=(Join-Path $env:ProgramData "EnterpriseIT\Api\database.config.dpapi");RecoveryResetSeconds=86400;RecoveryActions='restart/60000/restart/300000/""/0';StartService=$false}
}
function Invoke-ApiSc([string[]]$Arguments){& sc.exe @Arguments|Out-Null;if($LASTEXITCODE -ne 0){throw "API SCM provisioning failed with exit code $LASTEXITCODE."}}
function Protect-ApiDatabaseConfiguration([pscustomobject]$Plan,[Security.SecureString]$Secret){
 if($null -eq $Secret){throw "A SecureString API database URL is required for provisioning."}
 $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$Plan.ServiceHostPath;$start.Arguments='--provision-database-config "'+$Plan.DatabaseConfigPath+'" EnterpriseITApi';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $process=[Diagnostics.Process]::Start($start);$ptr=[IntPtr]::Zero;$plain=$null
 try{
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret);$plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  $process.StandardInput.Write($plain);$process.StandardInput.Close()
  $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync();$process.WaitForExit()
  $out=$outTask.GetAwaiter().GetResult();$err=$errTask.GetAwaiter().GetResult()
  if($process.ExitCode -ne 0 -or $out.Trim() -ne "OK" -or $err.Length -ne 0){throw "API DPAPI configuration provisioning failed without exposing secret details."}
 }finally{if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)};$plain=$null;$process.Dispose()}
}
function Invoke-ApiServiceProvisioning {
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
 param([Parameter(Mandatory=$true)][pscustomobject]$Plan,[Security.SecureString]$DatabaseUrl)
 if($WhatIfPreference){return [pscustomobject]@{serviceName=$Plan.ServiceName;serviceAccount=$Plan.ServiceAccount;serviceSidType=$Plan.ServiceSidType;installRoot=$Plan.InstallRoot;dryRun=$true;serviceStarted=$false;databaseConfigWritten=$false}}
 if($null -eq $DatabaseUrl){throw "A SecureString API database URL is required before provisioning can make changes."}
 foreach($file in @($Plan.ServiceHostPath,$Plan.NodePath,$Plan.ApiEntryPoint)){if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Required immutable API payload file is missing."}}
 $service=Get-CimInstance Win32_Service -Filter "Name='EnterpriseITApi'" -ErrorAction SilentlyContinue
 if($null -eq $service){if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Create dedicated virtual-account API service")){Invoke-ApiSc @("create",$Plan.ServiceName,"binPath=",('"'+$Plan.ServiceHostPath+'"'),"obj=",$Plan.ServiceAccount,"start=","auto","DisplayName=","Enterprise IT API")}}
 elseif($service.PathName -notlike "*$($Plan.ServiceHostPath)*" -or $service.StartName -ine $Plan.ServiceAccount){throw "Existing API service path or identity differs; refusing replacement."}
 if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Configure service SID and bounded SCM recovery")){Invoke-ApiSc @("sidtype",$Plan.ServiceName,"unrestricted");Invoke-ApiSc @("failure",$Plan.ServiceName,"reset=",[string]$Plan.RecoveryResetSeconds,"actions=",$Plan.RecoveryActions);Invoke-ApiSc @("failureflag",$Plan.ServiceName,"1")}
 $sidText=(& sc.exe showsid $Plan.ServiceName 2>&1|Out-String);if($LASTEXITCODE -ne 0){throw "Could not resolve API service SID."}
 $m=[regex]::Match($sidText,"S-1-5-80-(?:\d+-){4}\d+");if(-not $m.Success){throw "SCM returned an invalid API service SID."};$sid=$m.Value
 if($PSCmdlet.ShouldProcess($Plan.InstallRoot,"Apply immutable Program Files ACL")){& icacls.exe $Plan.InstallRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)") /T|Out-Host;if($LASTEXITCODE -ne 0){throw "Could not apply API installation ACL."}}
 if($PSCmdlet.ShouldProcess($Plan.DatabaseConfigPath,"Protect API database configuration with machine DPAPI")){
  New-Item -ItemType Directory -Path $Plan.DatabaseConfigRoot -Force|Out-Null
  & icacls.exe $Plan.DatabaseConfigRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)")|Out-Host
  if($LASTEXITCODE -ne 0){throw "Could not protect API database config directory."}
  Protect-ApiDatabaseConfiguration -Plan $Plan -Secret $DatabaseUrl
  if(-not(Test-Path -LiteralPath $Plan.DatabaseConfigPath -PathType Leaf)){throw "API DPAPI config file was not created."}
 }
 $sidState=(& sc.exe qsidtype $Plan.ServiceName 2>&1|Out-String);if($LASTEXITCODE -ne 0 -or $sidState -notmatch "UNRESTRICTED"){throw "API service SID is not unrestricted."}
 [pscustomobject]@{serviceName=$Plan.ServiceName;serviceAccount=$Plan.ServiceAccount;serviceSid=$sid;serviceSidType=$Plan.ServiceSidType;installRoot=$Plan.InstallRoot;recoveryPolicyConfigured=$true;installAclConfigured=$true;databaseConfigProtected=$true;databaseConfigAclConfigured=$true;serviceStarted=$false}
}
if($MyInvocation.InvocationName -ne "."){$p=Get-ApiServiceProvisioningPlan -InstallRoot $InstallRoot;Invoke-ApiServiceProvisioning -Plan $p -DatabaseUrl $DatabaseUrl|ConvertTo-Json -Depth 4}
