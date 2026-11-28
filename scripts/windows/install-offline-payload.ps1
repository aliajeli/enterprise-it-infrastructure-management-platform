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
 [ValidateRange(1,1024)][int]$MinimumFreeSpaceGB=10,
 # Database bootstrap inputs for a first install against a fresh PostgreSQL
 # cluster. They are validated here and forwarded verbatim to the
 # orchestration entry point; an empty BootstrapAdminUser means no bootstrap
 # (adopt an ownership-verified cluster instead).
 [string]$BootstrapAdminUser="",
 [Security.SecureString]$BootstrapAdminPassword,
 [string]$DatabaseName="enterprise_it",
 [string]$SchemaOwnerRole="enterprise_it_owner",
 [string]$MigrationRole="enterprise_it_migrator",
 [Security.SecureString]$MigrationPassword,
 [string]$ApiRuntimeRole="enterprise_it_api",
 [Security.SecureString]$ApiRuntimePassword,
 [string]$WorkerRuntimeRole="enterprise_it_worker",
 [Security.SecureString]$WorkerRuntimePassword
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Test-OfflineInstallerArchive {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$ArchivePath,[Parameter(Mandatory=$true)][string]$ExpectedSha256,[IO.FileStream]$ArchiveHandle)
 $archive=[IO.Path]::GetFullPath($ArchivePath)
 if($ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw "An independently obtained SHA-256 digest is required."}
 $ownsHandle=$null -eq $ArchiveHandle
 if($ownsHandle){$ArchiveHandle=Open-OfflineArchiveReadLock -ArchivePath $archive}
 try{
  $ArchiveHandle.Position=0
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$actual=[Convert]::ToHexString($sha.ComputeHash($ArchiveHandle))}finally{$sha.Dispose()}
  if(-not [string]::Equals($actual,$ExpectedSha256,[StringComparison]::OrdinalIgnoreCase)){throw "Offline payload archive digest does not match the trusted expected SHA-256 value."}
  $ArchiveHandle.Position=0
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipArchive]::new($ArchiveHandle,[IO.Compression.ZipArchiveMode]::Read,$true)
  try{
  # ZipArchive has already parsed its central directory here: this limit bounds
  # subsequent processing, not allocations during the initial ZIP parse.
  if($zip.Entries.Count -gt 250000){throw "Offline payload has too many ZIP entries."}
  $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $files=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
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
    if($segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(?:\..*)?$'){throw "ZIP entry uses a reserved Windows device name: $name"}
   }
   if(-not $names.Add($trimmed)){throw "Duplicate ZIP entry path is not allowed: $name"}
   if(-not $name.EndsWith('/')){[void]$files.Add($trimmed)}
   $unixType=($entry.ExternalAttributes -shr 16) -band 0xF000
   $dosAttributes=$entry.ExternalAttributes -band 0xFFFF
   if($unixType -eq 0xA000 -or ($dosAttributes -band 0x400) -ne 0){throw "Symbolic-link or reparse-point ZIP entries are not allowed: $name"}
   if(-not $name.EndsWith('/')){
    $totalExpanded += [int64]$entry.Length
    if($totalExpanded -gt 100GB){throw "Offline payload expands beyond the 100 GB safety limit."}
    if($trimmed -ieq 'package.json'){
     if($trimmed -cne 'package.json' -or $entry.Length -gt 1MB){throw "Offline package metadata is incorrectly named or too large."}
     $hasPackage=$true
    }
    if($trimmed -ieq 'payload.manifest.json'){
     if($trimmed -cne 'payload.manifest.json' -or $entry.Length -gt 64MB){throw "Offline payload manifest is incorrectly named or too large."}
     $hasManifest=$true
    }
   }
  }
  # Check after enumeration so input order cannot hide a file/directory
  # conflict. Do not accumulate a second set of implicit directories.
  foreach($name in $names){
   $slash=$name.IndexOf('/')
   while($slash -ge 0){
    $parent=$name.Substring(0,$slash)
    if($files.Contains($parent)){throw "ZIP entry is both a file and an ancestor directory: $parent"}
    $slash=$name.IndexOf('/',$slash+1)
   }
  }
  if(-not $hasPackage -or -not $hasManifest){throw "ZIP root must contain package.json and payload.manifest.json."}
   [pscustomobject]@{archive=$archive;sha256=$actual;entryCount=$zip.Entries.Count;expandedBytes=$totalExpanded}
  }finally{$zip.Dispose()}
 }finally{
  if($ownsHandle){$ArchiveHandle.Dispose()}else{$ArchiveHandle.Position=0}
 }
}

# Bound actual decompressed bytes as well as ZIP directory metadata. ZIP
# headers are untrusted and must not be the only memory-allocation limit.
function Read-BoundedOfflineUtf8Stream {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][IO.Stream]$InputStream,[Parameter(Mandatory=$true)][ValidateRange(1,67108864)][int]$MaximumBytes)
 $buffer=[byte[]]::new(65536);$memory=[IO.MemoryStream]::new()
 try{
  while(($read=$InputStream.Read($buffer,0,$buffer.Length)) -gt 0){
   if($memory.Length+$read -gt $MaximumBytes){throw 'Offline metadata exceeds its byte limit.'}
   $memory.Write($buffer,0,$read)
  }
  $bytes=$memory.ToArray()
  $offset=if($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf){3}else{0}
  return [Text.UTF8Encoding]::new($false,$true).GetString($bytes,$offset,$bytes.Length-$offset)
 }finally{$memory.Dispose()}
}
function Read-BoundedOfflineZipText {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][IO.Compression.ZipArchiveEntry]$Entry,[Parameter(Mandatory=$true)][int]$MaximumBytes)
 if($Entry.Length -gt $MaximumBytes){throw 'Offline metadata exceeds its declared byte limit.'}
 $stream=$Entry.Open()
 try{return (Read-BoundedOfflineUtf8Stream -InputStream $stream -MaximumBytes $MaximumBytes)}finally{$stream.Dispose()}
}

function Get-OfflineInstallerPlan {
 [CmdletBinding()]
 param([string]$PayloadArchive,[string]$ExpectedSha256,[IO.FileStream]$ArchiveHandle)
 $archivePlan=Test-OfflineInstallerArchive -ArchivePath $PayloadArchive -ExpectedSha256 $ExpectedSha256 -ArchiveHandle $ArchiveHandle
 $programFiles=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
 $base=Join-Path $programFiles 'EnterpriseIT'
 [pscustomobject]@{Archive=$archivePlan.archive;Sha256=$archivePlan.sha256;EntryCount=$archivePlan.entryCount;ExpandedBytes=$archivePlan.expandedBytes;BaseDirectory=$base}
}

function Open-OfflineArchiveReadLock {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$ArchivePath)
 $full=[IO.Path]::GetFullPath($ArchivePath)
 # Keep one non-write-sharing handle for digest validation, ZIP inspection and
 # extraction; all content reads use this handle even if an ancestor is renamed.
 return [IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
}

function Assert-OfflineInstallerCapability {
 # First capability gate for the offline installer. It replaces the former
 # unconditional "Offline installation is disabled pending PostgreSQL
 # initialization and ownership verification" throw: those capabilities now
 # exist and are CI-proven (first-install lifecycle, ownership verification,
 # database bootstrap), and orchestration's own capability gates run again
 # before any service change. This gate keeps only the read-only
 # installer-level checks fail-closed before staging: secure URL inputs,
 # Edge parameters, and the orchestration entry point beside the installer.
 # InstallerScriptRoot is a test seam for the missing-entry-point branch.
 [CmdletBinding()]
 param(
  [Security.SecureString]$ApiDatabaseUrl,
  [Security.SecureString]$WorkerDatabaseUrl,
  [string]$EdgeBindAddress,
  [string]$EdgeTlsHostname,
  [string]$EdgeCertificateThumbprint,
  [string]$InstallerScriptRoot=$PSScriptRoot
 )
 if($null -eq $ApiDatabaseUrl -or $null -eq $WorkerDatabaseUrl){throw "Separate SecureString API and Worker database URLs are required."}
 if([string]::IsNullOrWhiteSpace($EdgeBindAddress) -or [string]::IsNullOrWhiteSpace($EdgeTlsHostname) -or [string]::IsNullOrWhiteSpace($EdgeCertificateThumbprint)){throw "Edge bind address, TLS hostname and certificate thumbprint are required."}
 if(-not(Test-Path -LiteralPath (Join-Path $InstallerScriptRoot "orchestrate-windows-services.ps1") -PathType Leaf)){throw "Service orchestration entry point is missing beside the installer; no files or services were changed."}
}
if($MyInvocation.InvocationName -ne '.'){
 # Bootstrap inputs must be complete before any archive work: invalid
 # credential sets are rejected in WhatIf preview mode as well, matching
 # the database capability scripts. The WhatIf plan reports only whether a
 # bootstrap was requested - never any bootstrap value.
 $bootstrapRequested=-not [string]::IsNullOrWhiteSpace($BootstrapAdminUser)
 if($bootstrapRequested -and ($null -eq $BootstrapAdminPassword -or $null -eq $MigrationPassword -or $null -eq $ApiRuntimePassword -or $null -eq $WorkerRuntimePassword)){
  throw "Bootstrap requires admin, migration, API runtime and Worker runtime SecureString passwords."
 }
 $archiveLock=Open-OfflineArchiveReadLock -ArchivePath $PayloadArchive
 try{
 $plan=Get-OfflineInstallerPlan -PayloadArchive $PayloadArchive -ExpectedSha256 $ExpectedSha256 -ArchiveHandle $archiveLock
 if($WhatIfPreference){$plan|Add-Member -NotePropertyName bootstrapRequested -NotePropertyValue $bootstrapRequested -PassThru|ConvertTo-Json -Depth 4;return}
 # Capability gate (formerly the unconditional "offline installation is
 # disabled" throw): fail-closed read-only checks before any staging.
 Assert-OfflineInstallerCapability -ApiDatabaseUrl $ApiDatabaseUrl -WorkerDatabaseUrl $WorkerDatabaseUrl -EdgeBindAddress $EdgeBindAddress -EdgeTlsHostname $EdgeTlsHostname -EdgeCertificateThumbprint $EdgeCertificateThumbprint
 . (Join-Path $PSScriptRoot 'installer-preflight.ps1') -MinimumFreeSpaceGB $MinimumFreeSpaceGB
 $facts=Get-InstallerPreflightFacts
 $preflight=Test-InstallerPreflightFacts -Facts $facts -MinimumFreeSpaceGB $MinimumFreeSpaceGB
 # Stage on the host baseline. Product-level blockers (migration transport,
 # Windows Server security acceptance) stay enforced at their own
 # fail-closed layers: orchestration rolls back anything it started, and
 # the full product `ready` flag remains closed for Setup.exe.
 if(-not $preflight.hostReady){$preflight|ConvertTo-Json -Depth 6;throw "Windows installer host preflight failed; no files or services were changed."}
 $programFilesLocation=@($facts.Locations|Where-Object{$_.Name -eq 'ProgramFiles'})|Select-Object -First 1
 $requiredFreeBytes=[int64]$plan.ExpandedBytes+([int64]$MinimumFreeSpaceGB*1GB)
 if($null -eq $programFilesLocation -or [int64]$programFilesLocation.FreeBytes -lt $requiredFreeBytes){throw "Program Files volume lacks space for the expanded payload plus the configured free-space reserve."}
 if($PSCmdlet.ShouldProcess($plan.BaseDirectory,"Verify, stage and install the offline Enterprise IT payload")){
  if(-not(Test-Path -LiteralPath $plan.BaseDirectory -PathType Container)){New-Item -ItemType Directory -Path $plan.BaseDirectory -Force|Out-Null}
  $archiveLock.Position=0
  $manifestZip=[IO.Compression.ZipArchive]::new($archiveLock,[IO.Compression.ZipArchiveMode]::Read,$true)
  try{
   $manifestEntry=$manifestZip.GetEntry('payload.manifest.json')
   $packageEntry=$manifestZip.GetEntry('package.json')
   $manifest=(Read-BoundedOfflineZipText -Entry $manifestEntry -MaximumBytes 64MB)|ConvertFrom-Json -ErrorAction Stop
   $package=(Read-BoundedOfflineZipText -Entry $packageEntry -MaximumBytes 1MB)|ConvertFrom-Json -ErrorAction Stop
  }finally{$manifestZip.Dispose()}
  $version=[string]$package.version
  if($version -notmatch '^\d+\.\d+\.\d+$' -or $manifest.applicationVersion -ne $version){throw "Archive package and manifest versions are invalid or inconsistent."}
  $installRoot=Join-Path $plan.BaseDirectory $version
  if(Test-Path -LiteralPath $installRoot){throw "Versioned install directory already exists; immutable payloads are never overwritten."}
  $staging=Join-Path $plan.BaseDirectory ('.staging-'+[guid]::NewGuid().ToString('N'))
  try{
   New-Item -ItemType Directory -Path $staging -ErrorAction Stop|Out-Null
   $archiveLock.Position=0
   $zipForExtraction=[IO.Compression.ZipArchive]::new($archiveLock,[IO.Compression.ZipArchiveMode]::Read,$true)
   try{[IO.Compression.ZipFileExtensions]::ExtractToDirectory($zipForExtraction,$staging)}finally{$zipForExtraction.Dispose()}
   . (Join-Path $PSScriptRoot 'new-offline-payload-manifest.ps1') -PayloadRoot $staging
   $verified=Test-OfflinePayloadManifest -PayloadRoot $staging -ExpectedApplicationVersion $version
   if(-not $verified.valid){throw "Extracted payload manifest verification failed."}
   if(Test-Path -LiteralPath $installRoot){throw "Versioned install directory appeared during staging; refusing overwrite."}
   [IO.Directory]::Move($staging,$installRoot)
  }finally{if(Test-Path -LiteralPath $staging){Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue}}
  try{
   & (Join-Path $PSScriptRoot 'orchestrate-windows-services.ps1') -InstallRoot $installRoot -ApiDatabaseUrl $ApiDatabaseUrl -WorkerDatabaseUrl $WorkerDatabaseUrl -EdgeBindAddress $EdgeBindAddress -EdgeHttpsPort $EdgeHttpsPort -EdgeTlsHostname $EdgeTlsHostname -EdgeCertificateThumbprint $EdgeCertificateThumbprint -BootstrapAdminUser $BootstrapAdminUser -BootstrapAdminPassword $BootstrapAdminPassword -DatabaseName $DatabaseName -SchemaOwnerRole $SchemaOwnerRole -MigrationRole $MigrationRole -MigrationPassword $MigrationPassword -ApiRuntimeRole $ApiRuntimeRole -ApiRuntimePassword $ApiRuntimePassword -WorkerRuntimeRole $WorkerRuntimeRole -WorkerRuntimePassword $WorkerRuntimePassword -Confirm:$false
  }catch{
   throw "Payload $version was staged at '$installRoot', but service orchestration failed. The immutable payload was retained for diagnosis. $($_.Exception.Message)"
  }
 }
 }finally{$archiveLock.Dispose()}
}
