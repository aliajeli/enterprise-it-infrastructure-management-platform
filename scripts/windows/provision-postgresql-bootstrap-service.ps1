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
if($data -notmatch '\\PostgreSQL\\(\d{1,3})\\data$'){throw "PostgreSQL data root must include a version directory."}
$pgVersion=$Matches[1]
if($WhatIfPreference){[pscustomobject]@{serviceName=$serviceName;serviceAccount=$serviceAccount;installRoot=$root;dataRoot=$data;dryRun=$true;serviceStarted=$false}|ConvertTo-Json;return}
if(-not $PSCmdlet.ShouldProcess($serviceName,"Register and configure dedicated PostgreSQL bootstrap service and ACLs")){return}

# Data-directory creation and ACL work are performed exclusively by the
# elevated bootstrap executable through NtCreateFile with an explicit
# SECURITY_DESCRIPTOR at creation, handle-relative component opens, reparse/
# volume/file-ID validation and identity-checked rollback. This script never
# creates or re-ACLs the data chain by path (no New-Item/icacls on the data
# directories). The payload read grant below is a Program Files ACL operation
# outside the data-directory trust boundary.
$serviceCreated=$false
$expectedBin='"'+$exe+'"'
$expectedSid=$null
try{
 $existing=Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
 if($null -eq $existing){
  & sc.exe create $serviceName "binPath=" $expectedBin "obj=" $serviceAccount "start=" "demand" "DisplayName=" "Enterprise IT PostgreSQL Bootstrap"
  if($LASTEXITCODE -ne 0){throw "Bootstrap service registration failed."}
  $serviceCreated=$true
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
 $expectedSid=$bootstrapMatch.Value
 $postgresSid=([Security.Principal.NTAccount]"NT SERVICE\EnterpriseITPostgreSQL").Translate([Security.Principal.SecurityIdentifier])
 $postgresSidValue=$postgresSid.Value
 if($postgresSidValue -notmatch "^S-1-5-80-(?:\d+-){4}\d+$"){throw "PostgreSQL service SID is invalid."}
 & icacls.exe $root /grant:r ("*"+$bootstrapMatch.Value+":(OI)(CI)(RX)") /T|Out-Host
 if($LASTEXITCODE -ne 0){throw "Bootstrap payload ACL failed."}
 $provisionOutput=(& $exe --provision-data --bootstrap-sid $bootstrapMatch.Value --postgres-sid $postgresSidValue --pg-version $pgVersion 2>&1|Out-String)
 if($LASTEXITCODE -ne 0){throw "PostgreSQL data directory provisioning failed: $($provisionOutput.Trim())"}
}catch{
 if($serviceCreated){
  # Transactional rollback: delete the service this invocation created only
  # after its Path, Account and service identity are re-read from the SCM and
  # proven to match this run's values. Ambiguity fails closed and keeps the
  # service for operator inspection.
  $rollbackApproved=$false
  $current=Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
  if($null -ne $current -and $null -ne $expectedSid){
   $currentPath=([string]$current.PathName).Trim('"')
   $currentStart=[string]$current.StartName
   $sidStateNow=(& sc.exe qsidtype $serviceName 2>&1|Out-String)
   $qsidOk=($LASTEXITCODE -eq 0 -and $sidStateNow -match "UNRESTRICTED")
   $sidTextNow=(& sc.exe showsid $serviceName 2>&1|Out-String)
   $currentSid=$null
   if($LASTEXITCODE -eq 0){$sidNowMatch=[regex]::Match($sidTextNow,"S-1-5-80-(?:\d+-){4}\d+");if($sidNowMatch.Success){$currentSid=$sidNowMatch.Value}}
   $rollbackApproved=([string]::Equals($currentPath,$exe,[StringComparison]::OrdinalIgnoreCase) -and
     [string]::Equals($currentStart,$serviceAccount,[StringComparison]::OrdinalIgnoreCase) -and
     $qsidOk -and [string]::Equals($currentSid,$expectedSid,[StringComparison]::Ordinal))
  }
  if(-not $rollbackApproved){
   throw "Bootstrap service registration failed and the created service identity could not be proven; refusing to delete it."
  }
  & sc.exe delete $serviceName|Out-Null
  if($LASTEXITCODE -ne 0){throw "Bootstrap service rollback failed."}
 }
 throw
}
Write-Host "provisioned: service=$serviceName install-root=$root"
[pscustomobject]@{serviceName=$serviceName;serviceAccount=$serviceAccount;serviceSid=$expectedSid;postgresServiceSid=$postgresSidValue;dataRoot=$data;serviceStarted=$false;firewallChanged=$false}|ConvertTo-Json -Depth 3
