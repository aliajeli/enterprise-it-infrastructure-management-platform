[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
 [Parameter(Mandatory=$true)][string]$InstallRoot,
 [string]$DataRoot=(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data"),
 # Destructive and explicit: without this switch the PostgreSQL data
 # directory and all ProgramData state (Credential Vault, keyring) are
 # preserved. Nothing in ProgramData is ever removed implicitly.
 [switch]$PurgeData
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Managed services in reverse start order; the dedicated bootstrap service
# is removed last because a first install may have registered it.
function Get-OfflineUninstallServiceOrder {
 @("EnterpriseITEdge","EnterpriseITWeb","EnterpriseITWorker","EnterpriseITApi","EnterpriseITPostgreSQL","EnterpriseITPostgreSQLBootstrap")
}
function Resolve-OfflineUninstallInstallRoot {
 param([Parameter(Mandatory=$true)][string]$InstallRoot)
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
 if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be versioned Program Files payload."}
 if(-not(Test-Path -LiteralPath $root -PathType Container)){throw "Install root does not exist; nothing to uninstall."}
 $item=Get-Item -LiteralPath $root -Force
 if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Install root must not be a reparse point."}
 return $root
}
function Get-OfflineUninstallManagedService {
 param([Parameter(Mandatory=$true)][string]$ServiceName)
 Get-CimInstance Win32_Service -Filter ("Name='"+$ServiceName+"'") -ErrorAction SilentlyContinue
}
function Invoke-OfflinePayloadUninstall {
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
 param(
  [Parameter(Mandatory=$true)][string]$InstallRoot,
  [string]$DataRoot=(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data"),
  [switch]$PurgeData
 )
 $root=Resolve-OfflineUninstallInstallRoot -InstallRoot $InstallRoot
 # Ownership proof before any mutation: every managed service that exists
 # must run from this exact install root. A service we cannot place inside
 # the root is foreign and must not be stopped or deleted - fail closed.
 $existing=@()
 foreach($serviceName in Get-OfflineUninstallServiceOrder){
  $service=Get-OfflineUninstallManagedService -ServiceName $serviceName
  if($null -eq $service){continue}
  $pathName=[string]$service.PathName
  if($pathName.IndexOf($root,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Service '$serviceName' does not belong to install root '$root'; refusing to modify it."}
  $existing+=$serviceName
 }
 if($WhatIfPreference){
  return [pscustomobject]@{status="whatif";installRoot=$root;servicesToRemove=@($existing);installRootRemoved=$false;dataPurged=$false}|ConvertTo-Json -Depth 4
 }
 $removed=[Collections.Generic.List[string]]::new()
 foreach($serviceName in $existing){
  if(-not $PSCmdlet.ShouldProcess($serviceName,"Stop and delete managed service")){continue}
  $service=Get-OfflineUninstallManagedService -ServiceName $serviceName
  if($null -ne $service -and $service.State -eq "Running"){
   & sc.exe stop $serviceName|Out-Null
   $deadline=[DateTime]::UtcNow.AddSeconds(30)
   while([DateTime]::UtcNow -lt $deadline){
    $service=Get-OfflineUninstallManagedService -ServiceName $serviceName
    if($null -eq $service -or $service.State -ne "Running"){break}
    Start-Sleep -Milliseconds 500
   }
   $service=Get-OfflineUninstallManagedService -ServiceName $serviceName
   if($null -ne $service -and $service.State -eq "Running"){throw "Service '$serviceName' did not stop within 30 seconds; refusing to continue uninstall."}
  }
  if($null -ne (Get-OfflineUninstallManagedService -ServiceName $serviceName)){
   & sc.exe delete $serviceName|Out-Null
   if($null -ne (Get-OfflineUninstallManagedService -ServiceName $serviceName)){throw "Service '$serviceName' could not be deleted; refusing to continue uninstall."}
  }
  $removed.Add($serviceName)
 }
 $installRootRemoved=$false
 if($PSCmdlet.ShouldProcess($root,"Remove versioned install directory")){
  $reparseChild=@(Get-ChildItem -LiteralPath $root -Force|Where-Object{($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
  if($reparseChild.Count -gt 0){throw "Install root contains reparse-point children; refusing to remove it."}
  Remove-Item -LiteralPath $root -Recurse -Force
  if(Test-Path -LiteralPath $root){throw "Install root could not be removed."}
  $installRootRemoved=$true
 }
 $dataPurged=$false
 if($PurgeData){
  $dataFull=[IO.Path]::GetFullPath($DataRoot)
  if(Test-Path -LiteralPath $dataFull){
   $dataItem=Get-Item -LiteralPath $dataFull -Force
   if(($dataItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Data root must not be a reparse point."}
   if($PSCmdlet.ShouldProcess($dataFull,"Purge PostgreSQL data directory")){
    Remove-Item -LiteralPath $dataFull -Recurse -Force
    if(Test-Path -LiteralPath $dataFull){throw "PostgreSQL data directory could not be purged."}
    $dataPurged=$true
   }
  }
 }
 [pscustomobject]@{status="ok";installRoot=$root;servicesRemoved=@($removed);installRootRemoved=$installRootRemoved;dataPurged=$dataPurged;dataRootPreserved=(-not $dataPurged)}|ConvertTo-Json -Depth 4
}
if($MyInvocation.InvocationName -ne '.'){
 Invoke-OfflinePayloadUninstall -InstallRoot $InstallRoot -DataRoot $DataRoot -PurgeData:$PurgeData
}
