[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
 [Parameter(Mandatory=$true)][string]$InstallRoot,
 [string]$DataRoot=(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$serviceName="EnterpriseITPostgreSQLBootstrap"
$serviceAccount="NT SERVICE\EnterpriseITPostgreSQLBootstrap"
$root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
$parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be Program Files\EnterpriseIT\<version>."}
$exe=Join-Path $root "EnterpriseIT.PostgreSQLBootstrap.exe"
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw "Bootstrap service executable is missing."}
$data=[IO.Path]::GetFullPath($DataRoot)
$expected=[IO.Path]::GetFullPath((Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data"))
if(-not [string]::Equals($data,$expected,[StringComparison]::OrdinalIgnoreCase)){throw "PostgreSQL data root must be the fixed ProgramData location."}
if($WhatIfPreference){[pscustomobject]@{serviceName=$serviceName;serviceAccount=$serviceAccount;installRoot=$root;dataRoot=$data;dryRun=$true;serviceStarted=$false}|ConvertTo-Json;return}
if(-not $PSCmdlet.ShouldProcess($serviceName,"Register and configure dedicated PostgreSQL bootstrap service and ACLs")){return}
$existing=Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if($null -eq $existing){
 $bin='"'+$exe+'"'
 & sc.exe create $serviceName "binPath=" $bin "obj=" $serviceAccount "start=" "demand" "DisplayName=" "Enterprise IT PostgreSQL Bootstrap"
 if($LASTEXITCODE -ne 0){throw "Bootstrap service registration failed."}
}else{
 throw "Existing bootstrap service detected; refusing to adopt or modify it."
}
& sc.exe sidtype $serviceName unrestricted|Out-Null
if($LASTEXITCODE -ne 0){throw "Bootstrap service SID configuration failed."}
$sidState=(& sc.exe qsidtype $serviceName 2>&1|Out-String)
if($LASTEXITCODE -ne 0 -or $sidState -notmatch "UNRESTRICTED"){throw "Bootstrap service SID is not enabled."}
$bootstrapSidText=(& sc.exe showsid $serviceName 2>&1|Out-String)
if($LASTEXITCODE -ne 0){throw "Bootstrap service SID could not be resolved."}
$bootstrapMatch=[regex]::Match($bootstrapSidText,"S-1-5-80-(?:\d+-){4}\d+")
if(-not $bootstrapMatch.Success){throw "Bootstrap service SID is invalid."}
$postgresSid=([Security.Principal.NTAccount]"NT SERVICE\EnterpriseITPostgreSQL").Translate([Security.Principal.SecurityIdentifier])
$postgresSidValue=$postgresSid.Value
if($postgresSidValue -notmatch "^S-1-5-80-(?:\d+-){4}\d+$"){throw "PostgreSQL service SID is invalid."}
& icacls.exe $root /grant:r ("*"+$bootstrapMatch.Value+":(OI)(CI)(RX)") /T|Out-Host
if($LASTEXITCODE -ne 0){throw "Bootstrap payload ACL failed."}
$dataParent=Split-Path $data -Parent
New-Item -ItemType Directory -Path $dataParent -Force|Out-Null
& icacls.exe $dataParent /grant:r ("*"+$bootstrapMatch.Value+":(OI)(CI)(M)") ("*"+$postgresSidValue+":(OI)(CI)(M)")|Out-Host
if($LASTEXITCODE -ne 0){throw "PostgreSQL data parent ACL failed."}
New-Item -ItemType Directory -Path $data -Force|Out-Null
& icacls.exe $data /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$bootstrapMatch.Value+":(OI)(CI)(M)") ("*"+$postgresSidValue+":(OI)(CI)(M)") /T|Out-Host
if($LASTEXITCODE -ne 0){throw "PostgreSQL data ACL failed."}
[pscustomobject]@{serviceName=$serviceName;serviceAccount=$serviceAccount;serviceSid=$bootstrapMatch.Value;postgresServiceSid=$postgresSidValue;dataRoot=$data;serviceStarted=$false;firewallChanged=$false}|ConvertTo-Json -Depth 3
