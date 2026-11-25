[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param([Parameter(Mandatory=$true)][string]$InstallRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Get-WindowsServiceHostStagePlan([string]$InstallRoot){
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
 if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be Program Files\EnterpriseIT\<major.minor.patch>."}
 $repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
 $items=@(
  [pscustomobject]@{Service="EnterpriseITApi";Project=(Join-Path $repoRoot "apps\api\windows\service-host\EnterpriseIT.ApiServiceHost.csproj");Executable="EnterpriseIT.ApiServiceHost.exe"},
  [pscustomobject]@{Service="EnterpriseITWeb";Project=(Join-Path $repoRoot "apps\web\windows\service-host\EnterpriseIT.WebServiceHost.csproj");Executable="EnterpriseIT.WebServiceHost.exe"},
  [pscustomobject]@{Service="EnterpriseITWorker";Project=(Join-Path $repoRoot "apps\worker\windows\service-host\EnterpriseIT.WorkerServiceHost.csproj");Executable="EnterpriseIT.WorkerServiceHost.exe"},
  [pscustomobject]@{Service="EnterpriseITEdge";Project=(Join-Path $repoRoot "apps\edge\windows\service-host\EnterpriseIT.EdgeServiceHost.csproj");Executable="EnterpriseIT.EdgeServiceHost.exe"},
  [pscustomobject]@{Service="EnterpriseITKeyringStorageHelper";Project=(Join-Path $repoRoot "apps\api\windows\keyring-storage-helper\CredentialVault.KeyringStorageHelper.csproj");Executable="CredentialVault.KeyringStorageHelper.exe"},
  [pscustomobject]@{Service="EnterpriseITDpapiHelper";Project=(Join-Path $repoRoot "apps\api\windows\dpapi-helper\CredentialVault.DpapiHelper.csproj");Executable="CredentialVault.DpapiHelper.exe"},
  [pscustomobject]@{Service="EnterpriseITPostgreSQLBootstrap";Project=(Join-Path $repoRoot "apps\api\windows\postgresql-bootstrap\EnterpriseIT.PostgreSQLBootstrap.csproj");Executable="EnterpriseIT.PostgreSQLBootstrap.exe"}
 )
 [pscustomobject]@{InstallRoot=$root;RuntimeIdentifier="win-x64";SelfContained=$true;PublishSingleFile=$true;Services=$items;Immutable=$true}
}
if($MyInvocation.InvocationName -ne "."){
 $plan=Get-WindowsServiceHostStagePlan -InstallRoot $InstallRoot
 if($WhatIfPreference){[pscustomobject]@{installRoot=$plan.InstallRoot;services=@($plan.Services|ForEach-Object{$_.Service});runtimeIdentifier=$plan.RuntimeIdentifier;selfContained=$true;dryRun=$true}|ConvertTo-Json -Depth 4;return}
 if(-not $PSCmdlet.ShouldProcess($plan.InstallRoot,"Publish and stage seven self-contained Windows service hosts/helpers")){return}
 foreach($item in $plan.Services){
  if(-not(Test-Path -LiteralPath $item.Project -PathType Leaf)){throw "Service host project is missing: $($item.Project)"}
  $destination=Join-Path $plan.InstallRoot $item.Executable
  if(Test-Path -LiteralPath $destination){throw "Immutable service host payload already exists: $destination"}
 }
 New-Item -ItemType Directory -Path $plan.InstallRoot -Force|Out-Null
 $tempRoot=Join-Path ([IO.Path]::GetTempPath()) ("enterpriseit-hosts-"+[guid]::NewGuid().ToString("N"))
 $publishRoot=Join-Path $tempRoot "publish";$promotionRoot=Join-Path $tempRoot "promotion"
 $promoted=[System.Collections.Generic.List[string]]::new()
 New-Item -ItemType Directory -Path $publishRoot,$promotionRoot -Force|Out-Null
 try{
  # Publish every host before touching the immutable installation directory.
  foreach($item in $plan.Services){
   $output=Join-Path $publishRoot $item.Service
   $publishOutput=& dotnet publish $item.Project --configuration Release --runtime win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -p:DebugSymbols=false --output $output 2>&1 | Out-String
   if($LASTEXITCODE -ne 0){throw "Self-contained publish failed for $($item.Service): $publishOutput"}
   $source=Join-Path $output $item.Executable
   if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Expected single-file executable was not produced for $($item.Service)."}
   Copy-Item -LiteralPath $source -Destination (Join-Path $promotionRoot $item.Executable)
  }
  foreach($item in $plan.Services){
   $destination=Join-Path $plan.InstallRoot $item.Executable
   if(Test-Path -LiteralPath $destination){throw "Immutable service host destination appeared during promotion: $destination"}
  }
  # Promote only after every self-contained executable has been built and staged.
  foreach($item in $plan.Services){
   $source=Join-Path $promotionRoot $item.Executable
   $destination=Join-Path $plan.InstallRoot $item.Executable
   [IO.File]::Move($source,$destination)
   $promoted.Add($destination)
  }
  [pscustomobject]@{installRoot=$plan.InstallRoot;services=@($plan.Services|ForEach-Object{$_.Service});runtimeIdentifier="win-x64";selfContained=$true;singleFile=$true;atomicPromotion=$true;installerCreated=$false}|ConvertTo-Json -Depth 4
 }catch{
  $rollbackTargets=$promoted.ToArray()
  [Array]::Reverse($rollbackTargets)
  foreach($destination in $rollbackTargets){
   if(Test-Path -LiteralPath $destination){Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue}
  }
  throw
 }finally{if(Test-Path $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue}}
}
