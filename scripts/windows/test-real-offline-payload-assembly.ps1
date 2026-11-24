# Full payload assembly experiment on a disposable Windows CI runner only.
# No installer, services, cluster initialization, or release is created.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $env:RUNNER_TEMP){throw 'This assembly experiment requires a disposable Windows CI runner.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$package=Get-Content -LiteralPath (Join-Path $repo 'package.json') -Raw|ConvertFrom-Json
$version=[string]$package.version
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid application version.'}
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
$root=Join-Path $pf ('EnterpriseIT\'+$version)
$work=Join-Path $env:RUNNER_TEMP ('enterpriseit-assembly-'+[guid]::NewGuid().ToString('N'))
$archive=Join-Path $work 'experimental-payload.zip'
$extract=Join-Path $work 'extract'
$created=$false
if(Test-Path -LiteralPath $root){throw 'Version directory already exists; refusing to adopt or overwrite it.'}
try{
 New-Item -ItemType Directory -Path $work -ErrorAction Stop|Out-Null
 New-Item -ItemType Directory -Path $root -ErrorAction Stop|Out-Null
 $created=$true
 $runtime=Split-Path (Get-Command node.exe -ErrorAction Stop).Source -Parent
 & (Join-Path $PSScriptRoot 'stage-node-runtime.ps1') -NodeRuntimeDirectory $runtime -InstallRoot $root -Confirm:$false|Out-Null
 & (Join-Path $PSScriptRoot 'stage-node-application-runtime.ps1') -SourceRoot $repo -InstallRoot $root -Confirm:$false|Out-Null
 & (Join-Path $PSScriptRoot 'stage-migration-tool.ps1') -SourceRoot $repo -InstallRoot $root -Confirm:$false|Out-Null
 & (Join-Path $PSScriptRoot 'stage-web-standalone.ps1') -StandaloneDirectory (Join-Path $repo 'apps\web\.next\standalone') -InstallRoot $root -Confirm:$false|Out-Null
 & (Join-Path $PSScriptRoot 'stage-windows-service-hosts.ps1') -InstallRoot $root -Confirm:$false|Out-Null
 & (Join-Path $PSScriptRoot 'stage-postgresql.ps1') -InstallRoot $root -CacheDirectory (Join-Path $work 'downloads') -Confirm:$false|Out-Null
 Copy-Item -LiteralPath (Join-Path $repo 'package.json') -Destination $root
 Copy-Item -LiteralPath (Join-Path $repo 'package-lock.json') -Destination $root
 New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -ErrorAction Stop|Out-Null
 Copy-Item -LiteralPath $PSScriptRoot -Destination (Join-Path $root 'scripts\windows') -Recurse
 $result=& (Join-Path $PSScriptRoot 'new-offline-payload-package.ps1') -SourceRoot $root -OutputArchive $archive -Confirm:$false | ConvertFrom-Json
 if($result.status -ne 'created' -or $result.applicationVersion -ne $version -or $result.installerIncluded -or $result.signatureIncluded){throw 'Unexpected experimental archive result.'}
 $hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
 . (Join-Path $PSScriptRoot 'install-offline-payload.ps1') -PayloadArchive $archive -ExpectedSha256 $hash
 $plan=Get-OfflineInstallerPlan -PayloadArchive $archive -ExpectedSha256 $hash
 if($plan.EntryCount -lt 10){throw 'Experimental archive is unexpectedly small.'}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::ExtractToDirectory($archive,$extract)
 . (Join-Path $PSScriptRoot 'new-offline-payload-manifest.ps1') -PayloadRoot $extract
 $checked=Test-OfflinePayloadManifest -PayloadRoot $extract -ExpectedApplicationVersion $version
 if(-not $checked.valid -or $checked.fileCount -ne $result.payloadFileCount){throw 'Extracted experimental payload did not match its manifest.'}
 # Validate the isolated CLI and real schema from the extracted archive.
 & (Join-Path $PSScriptRoot 'test-migration-tool-offline.ps1') -Root $extract|Out-Null
 & (Join-Path $PSScriptRoot 'test-postgresql-migration-disposable.ps1') -PayloadRoot $extract -WorkRoot $work|Out-Null
 $blocked=$false
 try{& (Join-Path $PSScriptRoot 'install-offline-payload.ps1') -PayloadArchive $archive -ExpectedSha256 $hash -Confirm:$false|Out-Null}catch{
  $blocked=$_.Exception.Message -like '*Offline installation is disabled*no files or services were changed*'
 }
 if(-not $blocked){throw 'Real experimental archive must not bypass the disabled installer gate.'}
 Write-Host 'Real disposable payload assembly and archive checks passed; installer remains disabled, no artifact released.'
}finally{
 if($created -and (Test-Path -LiteralPath $root)){
  $item=Get-Item -LiteralPath $root -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Refusing to remove a replaced assembly root.'}
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
 }
 if((Test-Path -LiteralPath $work) -and -not(Test-Path -LiteralPath (Join-Path $work 'DO_NOT_DELETE_RUNNING_POSTGRES'))){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
}
