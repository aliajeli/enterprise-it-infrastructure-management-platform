[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
 [Parameter(Mandatory=$true)][string]$PayloadArchive,
 [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
 [Security.SecureString]$ApiDatabaseUrl,
 [Security.SecureString]$WorkerDatabaseUrl,
 [string]$EdgeBindAddress,
 [int]$EdgeHttpsPort=443,
 [string]$EdgeTlsHostname,
 [string]$EdgeCertificateThumbprint,
 [ValidateRange(1,1024)][int]$MinimumFreeSpaceGB=10
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Test-OfflineInstallerArchive {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$ArchivePath,[Parameter(Mandatory=$true)][string]$ExpectedSha256)
 $archive=[IO.Path]::GetFullPath($ArchivePath)
 if(-not(Test-Path -LiteralPath $archive -PathType Leaf)){throw "Offline payload archive does not exist."}
 if($ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw "An independently obtained SHA-256 digest is required."}
 $actual=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
 if(-not [string]::Equals($actual,$ExpectedSha256,[StringComparison]::OrdinalIgnoreCase)){throw "Offline payload archive digest does not match the trusted expected SHA-256 value."}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($archive)
 try{
  $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $hasPackage=$false;$hasManifest=$false
  [int64]$totalExpanded=0
  foreach($entry in $zip.Entries){
   $name=[string]$entry.FullName
   if([string]::IsNullOrWhiteSpace($name) -or $name.Contains('\') -or $name.StartsWith('/') -or $name -match '^[A-Za-z]:' ){throw "Unsafe ZIP entry path: $name"}
   $trimmed=$name.TrimEnd('/')
   if([string]::IsNullOrWhiteSpace($trimmed)){throw "Empty ZIP entry path is not allowed."}
   $segments=@($trimmed.Split('/'))
   if(@($segments|Where-Object{$_ -eq '.' -or $_ -eq '..' -or $_ -eq ''}).Count -gt 0){throw "ZIP entry contains an unsafe path segment: $name"}
   foreach($segment in $segments){
    if($segment -match '[\x00-\x1F<>:"|?*]' -or $segment.EndsWith('.') -or $segment.EndsWith(' ')){throw "ZIP entry contains a Windows-invalid path segment: $name"}
    if($segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?
   if(-not $name.EndsWith('/')){
    $totalExpanded += [int64]$entry.Length
    if($totalExpanded -gt 100GB){throw "Offline payload expands beyond the 100 GB safety limit."}
    if($trimmed -eq 'package.json'){$hasPackage=$true}
    if($trimmed -eq 'payload.manifest.json'){$hasManifest=$true}
   }
  }
  if(-not $hasPackage -or -not $hasManifest){throw "ZIP root must contain package.json and payload.manifest.json."}
  [pscustomobject]@{archive=$archive;sha256=$actual;entryCount=$zip.Entries.Count;expandedBytes=$totalExpanded}
 }finally{$zip.Dispose()}
}

function Get-OfflineInstallerPlan {
 [CmdletBinding()]
 param([string]$PayloadArchive,[string]$ExpectedSha256)
 $archivePlan=Test-OfflineInstallerArchive -ArchivePath $PayloadArchive -ExpectedSha256 $ExpectedSha256
 $programFiles=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
 $base=Join-Path $programFiles 'EnterpriseIT'
 [pscustomobject]@{Archive=$archivePlan.archive;Sha256=$archivePlan.sha256;EntryCount=$archivePlan.entryCount;ExpandedBytes=$archivePlan.expandedBytes;BaseDirectory=$base}
}

if($MyInvocation.InvocationName -ne '.'){
 $plan=Get-OfflineInstallerPlan -PayloadArchive $PayloadArchive -ExpectedSha256 $ExpectedSha256
 if($WhatIfPreference){$plan|ConvertTo-Json -Depth 4;return}
 if($null -eq $ApiDatabaseUrl -or $null -eq $WorkerDatabaseUrl){throw "Separate SecureString API and Worker database URLs are required."}
 if([string]::IsNullOrWhiteSpace($EdgeBindAddress) -or [string]::IsNullOrWhiteSpace($EdgeTlsHostname) -or [string]::IsNullOrWhiteSpace($EdgeCertificateThumbprint)){throw "Edge bind address, TLS hostname and certificate thumbprint are required."}
 . (Join-Path $PSScriptRoot 'installer-preflight.ps1') -MinimumFreeSpaceGB $MinimumFreeSpaceGB
 $facts=Get-InstallerPreflightFacts
 $preflight=Test-InstallerPreflightFacts -Facts $facts -MinimumFreeSpaceGB $MinimumFreeSpaceGB
 if(-not $preflight.ready){$preflight|ConvertTo-Json -Depth 6;throw "Windows installer host preflight failed; no files or services were changed."}
 $programFilesLocation=@($facts.Locations|Where-Object{$_.Name -eq 'ProgramFiles'})|Select-Object -First 1
 $requiredFreeBytes=[int64]$plan.ExpandedBytes+([int64]$MinimumFreeSpaceGB*1GB)
 if($null -eq $programFilesLocation -or [int64]$programFilesLocation.FreeBytes -lt $requiredFreeBytes){throw "Program Files volume lacks space for the expanded payload plus the configured free-space reserve."}
 if($PSCmdlet.ShouldProcess($plan.BaseDirectory,"Verify, stage and install the offline Enterprise IT payload")){
  if(-not(Test-Path -LiteralPath $plan.BaseDirectory -PathType Container)){New-Item -ItemType Directory -Path $plan.BaseDirectory -Force|Out-Null}
  $manifestZip=[IO.Compression.ZipFile]::OpenRead($plan.Archive)
  try{
   $manifestEntry=$manifestZip.GetEntry('payload.manifest.json')
   $packageEntry=$manifestZip.GetEntry('package.json')
   $manifestReader=[IO.StreamReader]::new($manifestEntry.Open())
   try{$manifest=$manifestReader.ReadToEnd()|ConvertFrom-Json -ErrorAction Stop}finally{$manifestReader.Dispose()}
   $packageReader=[IO.StreamReader]::new($packageEntry.Open())
   try{$package=$packageReader.ReadToEnd()|ConvertFrom-Json -ErrorAction Stop}finally{$packageReader.Dispose()}
  }finally{$manifestZip.Dispose()}
  $version=[string]$package.version
  if($version -notmatch '^\d+\.\d+\.\d+$' -or $manifest.applicationVersion -ne $version){throw "Archive package and manifest versions are invalid or inconsistent."}
  $installRoot=Join-Path $plan.BaseDirectory $version
  if(Test-Path -LiteralPath $installRoot){throw "Versioned install directory already exists; immutable payloads are never overwritten."}
  $staging=Join-Path $plan.BaseDirectory ('.staging-'+[guid]::NewGuid().ToString('N'))
  try{
   New-Item -ItemType Directory -Path $staging -ErrorAction Stop|Out-Null
   [IO.Compression.ZipFile]::ExtractToDirectory($plan.Archive,$staging)
   . (Join-Path $PSScriptRoot 'new-offline-payload-manifest.ps1') -PayloadRoot $staging
   $verified=Test-OfflinePayloadManifest -PayloadRoot $staging -ExpectedApplicationVersion $version
   if(-not $verified.valid){throw "Extracted payload manifest verification failed."}
   if(Test-Path -LiteralPath $installRoot){throw "Versioned install directory appeared during staging; refusing overwrite."}
   [IO.Directory]::Move($staging,$installRoot)
  }finally{if(Test-Path -LiteralPath $staging){Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue}}
  try{
   & (Join-Path $PSScriptRoot 'orchestrate-windows-services.ps1') -InstallRoot $installRoot -ApiDatabaseUrl $ApiDatabaseUrl -WorkerDatabaseUrl $WorkerDatabaseUrl -EdgeBindAddress $EdgeBindAddress -EdgeHttpsPort $EdgeHttpsPort -EdgeTlsHostname $EdgeTlsHostname -EdgeCertificateThumbprint $EdgeCertificateThumbprint -Confirm:$false
  }catch{
   throw "Payload $version was staged at '$installRoot', but service orchestration failed. The immutable payload was retained for diagnosis. $($_.Exception.Message)"
  }
 }
}
){throw "ZIP entry uses a reserved Windows device name: $name"}
   }
   if(-not $names.Add($trimmed)){throw "Duplicate ZIP entry path is not allowed: $name"}
   $unixType=($entry.ExternalAttributes -shr 16) -band 0xF000
   $dosAttributes=$entry.ExternalAttributes -band 0xFFFF
   if($unixType -eq 0xA000 -or ($dosAttributes -band 0x400) -ne 0){throw "Symbolic-link or reparse-point ZIP entries are not allowed: $name"}
   if(-not $name.EndsWith('/')){
    $totalExpanded += [int64]$entry.Length
    if($totalExpanded -gt 100GB){throw "Offline payload expands beyond the 100 GB safety limit."}
    if($trimmed -eq 'package.json'){$hasPackage=$true}
    if($trimmed -eq 'payload.manifest.json'){$hasManifest=$true}
   }
  }
  if(-not $hasPackage -or -not $hasManifest){throw "ZIP root must contain package.json and payload.manifest.json."}
  [pscustomobject]@{archive=$archive;sha256=$actual;entryCount=$zip.Entries.Count;expandedBytes=$totalExpanded}
 }finally{$zip.Dispose()}
}

function Get-OfflineInstallerPlan {
 [CmdletBinding()]
 param([string]$PayloadArchive,[string]$ExpectedSha256)
 $archivePlan=Test-OfflineInstallerArchive -ArchivePath $PayloadArchive -ExpectedSha256 $ExpectedSha256
 $programFiles=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
 $base=Join-Path $programFiles 'EnterpriseIT'
 [pscustomobject]@{Archive=$archivePlan.archive;Sha256=$archivePlan.sha256;EntryCount=$archivePlan.entryCount;ExpandedBytes=$archivePlan.expandedBytes;BaseDirectory=$base}
}

if($MyInvocation.InvocationName -ne '.'){
 $plan=Get-OfflineInstallerPlan -PayloadArchive $PayloadArchive -ExpectedSha256 $ExpectedSha256
 if($WhatIfPreference){$plan|ConvertTo-Json -Depth 4;return}
 if($null -eq $ApiDatabaseUrl -or $null -eq $WorkerDatabaseUrl){throw "Separate SecureString API and Worker database URLs are required."}
 if([string]::IsNullOrWhiteSpace($EdgeBindAddress) -or [string]::IsNullOrWhiteSpace($EdgeTlsHostname) -or [string]::IsNullOrWhiteSpace($EdgeCertificateThumbprint)){throw "Edge bind address, TLS hostname and certificate thumbprint are required."}
 . (Join-Path $PSScriptRoot 'installer-preflight.ps1') -MinimumFreeSpaceGB $MinimumFreeSpaceGB
 $facts=Get-InstallerPreflightFacts
 $preflight=Test-InstallerPreflightFacts -Facts $facts -MinimumFreeSpaceGB $MinimumFreeSpaceGB
 if(-not $preflight.ready){$preflight|ConvertTo-Json -Depth 6;throw "Windows installer host preflight failed; no files or services were changed."}
 $programFilesLocation=@($facts.Locations|Where-Object{$_.Name -eq 'ProgramFiles'})|Select-Object -First 1
 $requiredFreeBytes=[int64]$plan.ExpandedBytes+([int64]$MinimumFreeSpaceGB*1GB)
 if($null -eq $programFilesLocation -or [int64]$programFilesLocation.FreeBytes -lt $requiredFreeBytes){throw "Program Files volume lacks space for the expanded payload plus the configured free-space reserve."}
 if($PSCmdlet.ShouldProcess($plan.BaseDirectory,"Verify, stage and install the offline Enterprise IT payload")){
  if(-not(Test-Path -LiteralPath $plan.BaseDirectory -PathType Container)){New-Item -ItemType Directory -Path $plan.BaseDirectory -Force|Out-Null}
  $manifestZip=[IO.Compression.ZipFile]::OpenRead($plan.Archive)
  try{
   $manifestEntry=$manifestZip.GetEntry('payload.manifest.json')
   $packageEntry=$manifestZip.GetEntry('package.json')
   $manifestReader=[IO.StreamReader]::new($manifestEntry.Open())
   try{$manifest=$manifestReader.ReadToEnd()|ConvertFrom-Json -ErrorAction Stop}finally{$manifestReader.Dispose()}
   $packageReader=[IO.StreamReader]::new($packageEntry.Open())
   try{$package=$packageReader.ReadToEnd()|ConvertFrom-Json -ErrorAction Stop}finally{$packageReader.Dispose()}
  }finally{$manifestZip.Dispose()}
  $version=[string]$package.version
  if($version -notmatch '^\d+\.\d+\.\d+$' -or $manifest.applicationVersion -ne $version){throw "Archive package and manifest versions are invalid or inconsistent."}
  $installRoot=Join-Path $plan.BaseDirectory $version
  if(Test-Path -LiteralPath $installRoot){throw "Versioned install directory already exists; immutable payloads are never overwritten."}
  $staging=Join-Path $plan.BaseDirectory ('.staging-'+[guid]::NewGuid().ToString('N'))
  try{
   New-Item -ItemType Directory -Path $staging -ErrorAction Stop|Out-Null
   [IO.Compression.ZipFile]::ExtractToDirectory($plan.Archive,$staging)
   . (Join-Path $PSScriptRoot 'new-offline-payload-manifest.ps1') -PayloadRoot $staging
   $verified=Test-OfflinePayloadManifest -PayloadRoot $staging -ExpectedApplicationVersion $version
   if(-not $verified.valid){throw "Extracted payload manifest verification failed."}
   if(Test-Path -LiteralPath $installRoot){throw "Versioned install directory appeared during staging; refusing overwrite."}
   [IO.Directory]::Move($staging,$installRoot)
  }finally{if(Test-Path -LiteralPath $staging){Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue}}
  try{
   & (Join-Path $PSScriptRoot 'orchestrate-windows-services.ps1') -InstallRoot $installRoot -ApiDatabaseUrl $ApiDatabaseUrl -WorkerDatabaseUrl $WorkerDatabaseUrl -EdgeBindAddress $EdgeBindAddress -EdgeHttpsPort $EdgeHttpsPort -EdgeTlsHostname $EdgeTlsHostname -EdgeCertificateThumbprint $EdgeCertificateThumbprint -Confirm:$false
  }catch{
   throw "Payload $version was staged at '$installRoot', but service orchestration failed. The immutable payload was retained for diagnosis. $($_.Exception.Message)"
  }
 }
}
