[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
 [Parameter(Mandatory=$true)][string]$SourceRoot,
 [Parameter(Mandatory=$true)][string]$OutputArchive
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot "new-offline-payload-manifest.ps1") -PayloadRoot $env:TEMP

function Get-OfflinePayloadPackagePlan {
 [CmdletBinding()]
 param([string]$SourceRoot,[string]$OutputArchive)
 $source=[IO.Path]::GetFullPath($SourceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not(Test-Path -LiteralPath $source -PathType Container)){throw "Offline payload source root does not exist."}
 $sourceItem=Get-Item -LiteralPath $source -Force
 if(($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Offline payload source root must not be a reparse point."}
 # Inspect the complete source tree before Copy-Item can traverse a junction or symbolic link.
 Get-OfflinePayloadInventory -PayloadRoot $source|Out-Null
 $manifestPath=Join-Path $source "package.json"
 if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Root package.json is missing from the staged payload."}
 $package=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -ErrorAction Stop
 $version=[string]$package.version
 if($version -notmatch '^\d+\.\d+\.\d+$'){throw "Root package version is invalid."}
 $required=@(
  "runtime\node.exe","runtime\npm.cmd",
  "EnterpriseIT.ApiServiceHost.exe","EnterpriseIT.WebServiceHost.exe","EnterpriseIT.WorkerServiceHost.exe","EnterpriseIT.EdgeServiceHost.exe",
  "CredentialVault.KeyringStorageHelper.exe","CredentialVault.DpapiHelper.exe",
  "apps\api\dist\server.js","apps\worker\dist\main.js","packages\database\dist\index.js",
  "packages\database\prisma\schema.prisma","packages\database\prisma\migrations",
  "node_modules\@platform\api\package.json","node_modules\@platform\worker\package.json","node_modules\@platform\database\package.json",
  "node_modules\fastify\package.json","node_modules\@node-rs\argon2\package.json",
  "apps\web\.next\standalone\server.js","apps\web\.next\standalone\node_modules\next\package.json",
  "postgresql\pgsql\bin\postgres.exe","postgresql\pgsql\bin\pg_ctl.exe","postgresql\pgsql\bin\initdb.exe",
  "postgresql\pgsql\share\postgresql.conf.sample",
  "scripts\windows\bootstrap-postgresql-database.ps1","scripts\windows\invoke-postgresql-migrations.ps1","scripts\windows\orchestrate-windows-services.ps1",
  "scripts\windows\provision-postgresql-service.ps1","scripts\windows\provision-api-service.ps1","scripts\windows\provision-worker-service.ps1",
  "scripts\windows\provision-web-service.ps1","scripts\windows\provision-edge-service.ps1",
  "scripts\windows\installer-preflight.ps1","scripts\windows\new-offline-payload-manifest.ps1","scripts\windows\install-offline-payload.ps1"
 )
 foreach($relative in $required){if(-not(Test-Path -LiteralPath (Join-Path $source $relative))){throw "Required offline payload component is missing: $relative"}}
 $archive=[IO.Path]::GetFullPath($OutputArchive)
 if([IO.Path]::GetExtension($archive) -ine ".zip"){throw "Output archive must use the .zip extension."}
 if($archive.StartsWith(($source+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Output archive must not be inside the source payload."}
 $hashPath=$archive+".sha256"
 if((Test-Path -LiteralPath $archive) -or (Test-Path -LiteralPath $hashPath)){throw "Output archive or checksum already exists; refusing to overwrite."}
 [pscustomobject]@{SourceRoot=$source;OutputArchive=$archive;ChecksumPath=$hashPath;ApplicationVersion=$version;RequiredFiles=$required}
}
if($MyInvocation.InvocationName -ne "."){
 $plan=Get-OfflinePayloadPackagePlan -SourceRoot $SourceRoot -OutputArchive $OutputArchive
 if($WhatIfPreference){[pscustomobject]@{sourceRoot=$plan.SourceRoot;outputArchive=$plan.OutputArchive;checksumPath=$plan.ChecksumPath;applicationVersion=$plan.ApplicationVersion;requiredComponents=$plan.RequiredFiles.Count;overwrite=$false;dryRun=$true}|ConvertTo-Json -Depth 4;return}
 if(-not $PSCmdlet.ShouldProcess($plan.OutputArchive,"Create immutable offline ZIP payload and SHA-256 checksum")){return}
 $parent=Split-Path $plan.OutputArchive -Parent
 if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw "Output directory must already exist: $parent"}
 $work=Join-Path $parent (".enterpriseit-payload-"+[guid]::NewGuid().ToString("N"))
 $archiveTemp=$plan.OutputArchive+".staging."+[guid]::NewGuid().ToString("N")
 $checksumTemp=$plan.ChecksumPath+".staging."+[guid]::NewGuid().ToString("N")
 $promotedArchive=$false
 try{
  New-Item -ItemType Directory -Path $work -ErrorAction Stop|Out-Null
  foreach($item in Get-ChildItem -LiteralPath $plan.SourceRoot -Force){Copy-Item -LiteralPath $item.FullName -Destination $work -Recurse}
  $created=New-OfflinePayloadManifest -PayloadRoot $work -ApplicationVersion $plan.ApplicationVersion -Reproducible
  $verified=Test-OfflinePayloadManifest -PayloadRoot $work -ExpectedApplicationVersion $plan.ApplicationVersion
  if(-not $verified.valid -or $verified.fileCount -ne $created.fileCount){throw "Offline payload manifest verification failed before archive creation."}
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  # Stable order, timestamps and attributes make the archive reproducible for
  # identical inputs on the same .NET toolchain. Empty directories contain no
  # payload files and are intentionally omitted.
  [string[]]$entries=@(Get-OfflinePayloadInventory -PayloadRoot $work|ForEach-Object{$_.path})+@('payload.manifest.json')
  [Array]::Sort($entries,[StringComparer]::Ordinal)
  $stream=[IO.File]::Open($archiveTemp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
   $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true,[Text.Encoding]::UTF8)
   try{
    foreach($relative in $entries){
     $entry=$zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
     $entry.LastWriteTime=[DateTimeOffset]::Parse('2000-01-01T00:00:00Z',[Globalization.CultureInfo]::InvariantCulture)
     $entry.ExternalAttributes=0
     $input=[IO.File]::OpenRead((Join-Path $work ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))))
     try{$output=$entry.Open();try{$input.CopyTo($output)}finally{$output.Dispose()}}finally{$input.Dispose()}
    }
   }finally{$zip.Dispose()}
  }finally{$stream.Dispose()}
  $archiveHash=(Get-FileHash -LiteralPath $archiveTemp -Algorithm SHA256).Hash.ToLowerInvariant()
  [IO.File]::WriteAllText($checksumTemp,($archiveHash+"  "+[IO.Path]::GetFileName($plan.OutputArchive)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
  if((Test-Path -LiteralPath $plan.OutputArchive) -or (Test-Path -LiteralPath $plan.ChecksumPath)){throw "Output destination appeared during packaging; refusing overwrite."}
  [IO.File]::Move($archiveTemp,$plan.OutputArchive);$promotedArchive=$true
  [IO.File]::Move($checksumTemp,$plan.ChecksumPath)
  [pscustomobject]@{status="created";applicationVersion=$plan.ApplicationVersion;archive=$plan.OutputArchive;sha256=$archiveHash;checksumFile=$plan.ChecksumPath;payloadFileCount=$verified.fileCount;payloadBytes=$verified.totalBytes;manifestVerified=$true;signatureIncluded=$false;installerIncluded=$false}|ConvertTo-Json -Depth 4
 }catch{
  if($promotedArchive -and (Test-Path -LiteralPath $plan.OutputArchive)){Remove-Item -LiteralPath $plan.OutputArchive -Force -ErrorAction SilentlyContinue}
  throw
 }finally{
  foreach($path in @($work,$archiveTemp,$checksumTemp)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue}}
 }
}
