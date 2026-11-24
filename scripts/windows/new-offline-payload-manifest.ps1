[CmdletBinding()]
param([ValidateSet("Create","Verify")][string]$Action="Create",[Parameter(Mandatory=$true)][string]$PayloadRoot,[string]$ApplicationVersion)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$script:OfflinePayloadManifestName="payload.manifest.json"
function Get-OfflinePayloadInventory {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$PayloadRoot)
 $root=[IO.Path]::GetFullPath($PayloadRoot)
 if(-not(Test-Path -LiteralPath $root -PathType Container)){throw "Payload root does not exist: $root"}
 $rootItem=Get-Item -LiteralPath $root -Force
 if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Payload root must not be a reparse point."}
 $files=[System.Collections.Generic.List[object]]::new()
 $pending=[System.Collections.Generic.Stack[string]]::new();$pending.Push($root)
 while($pending.Count -gt 0){
  $directory=$pending.Pop()
  foreach($item in Get-ChildItem -LiteralPath $directory -Force){
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Reparse points are not allowed: $($item.FullName)"}
   if($item.PSIsContainer){$pending.Push($item.FullName);continue}
   if($item.Name -eq $script:OfflinePayloadManifestName -and $item.DirectoryName -eq $root){continue}
   $relative=$item.FullName.Substring($root.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Replace([IO.Path]::DirectorySeparatorChar,"/").Replace([IO.Path]::AltDirectorySeparatorChar,"/")
   $hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
   $files.Add([pscustomobject]@{path=$relative;size=[int64]$item.Length;sha256=$hash})
  }
 }
 # Ordinal ordering avoids locale-dependent manifest and archive bytes.
 $byPath=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($file in $files){$byPath.Add([string]$file.path,$file)}
 [string[]]$paths=@($byPath.Keys)
 [Array]::Sort($paths,[StringComparer]::Ordinal)
 foreach($path in $paths){$byPath[$path]}
}
function New-OfflinePayloadManifest {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$PayloadRoot,[Parameter(Mandatory=$true)][string]$ApplicationVersion,[switch]$Reproducible)
 if($ApplicationVersion -notmatch '^\d+\.\d+\.\d+$'){throw "Application version must use major.minor.patch format."}
 $root=[IO.Path]::GetFullPath($PayloadRoot);$manifestPath=Join-Path $root $script:OfflinePayloadManifestName
 if(Test-Path -LiteralPath $manifestPath){throw "Manifest exists; refusing to overwrite immutable metadata."}
 $inventory=@(Get-OfflinePayloadInventory -PayloadRoot $root)
 if($inventory.Count -eq 0){throw "Cannot create a manifest for an empty payload."}
 $manifest=[ordered]@{schemaVersion=1;applicationVersion=$ApplicationVersion}
 # Reproducible archives deliberately omit wall-clock creation time; the fixed
 # archive timestamp is metadata normalization, not a claim about build time.
 if($Reproducible){$manifest['archiveTimestampUtc']='2000-01-01T00:00:00Z'}else{$manifest['createdUtc']=[DateTime]::UtcNow.ToString("o")}
 $manifest['hashAlgorithm']='SHA-256';$manifest['files']=$inventory
 [IO.File]::WriteAllText($manifestPath,(($manifest|ConvertTo-Json -Depth 8)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
 [pscustomobject]@{manifestPath=$manifestPath;applicationVersion=$ApplicationVersion;fileCount=$inventory.Count;totalBytes=[int64](($inventory|Measure-Object -Property size -Sum).Sum);created=$true}
}
function Test-OfflinePayloadManifest {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$PayloadRoot,[string]$ExpectedApplicationVersion)
 $root=[IO.Path]::GetFullPath($PayloadRoot);$manifestPath=Join-Path $root $script:OfflinePayloadManifestName
 if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Offline payload manifest is missing."}
 $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -ErrorAction Stop
 if($manifest.schemaVersion -ne 1 -or $manifest.hashAlgorithm -ne "SHA-256"){throw "Unsupported manifest schema or hash algorithm."}
 if($manifest.applicationVersion -notmatch '^\d+\.\d+\.\d+$'){throw "Manifest application version is invalid."}
 if($ExpectedApplicationVersion -and $manifest.applicationVersion -ne $ExpectedApplicationVersion){throw "Payload version mismatch."}
 if($null -eq $manifest.files -or @($manifest.files).Count -eq 0){throw "Manifest contains no payload files."}
 $expected=@{}
 foreach($entry in $manifest.files){
  $relative=[string]$entry.path;$segments=@($relative.Split("/"))
  if([string]::IsNullOrWhiteSpace($relative)-or $relative.Contains([char]92)-or $relative.StartsWith("/")-or $relative -match '^[A-Za-z]:' -or @($segments|Where-Object{$_ -eq ".." -or $_ -eq "." -or $_ -eq ""}).Count -gt 0){throw "Unsafe manifest path: $relative"}
  if($relative -eq $script:OfflinePayloadManifestName -or $expected.ContainsKey($relative)){throw "Duplicate or reserved manifest path: $relative"}
  if([string]$entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [int64]$entry.size -lt 0){throw "Invalid file metadata: $relative"}
  $expected[$relative]=$entry
 }
 $actual=@(Get-OfflinePayloadInventory -PayloadRoot $root)
 if($actual.Count -ne $expected.Count){throw "Payload file count differs from manifest."}
 foreach($file in $actual){
  if(-not $expected.ContainsKey($file.path)){throw "Unexpected payload file: $($file.path)"}
  $entry=$expected[$file.path]
  if([int64]$entry.size -ne $file.size -or -not [string]::Equals([string]$entry.sha256,[string]$file.sha256,[StringComparison]::OrdinalIgnoreCase)){throw "Payload integrity check failed: $($file.path)"}
 }
 [pscustomobject]@{valid=$true;applicationVersion=$manifest.applicationVersion;fileCount=$actual.Count;totalBytes=[int64](($actual|Measure-Object -Property size -Sum).Sum)}
}
if($MyInvocation.InvocationName -ne "."){
 if($Action -eq "Create"){if(-not $ApplicationVersion){throw "ApplicationVersion is required."};New-OfflinePayloadManifest -PayloadRoot $PayloadRoot -ApplicationVersion $ApplicationVersion|ConvertTo-Json -Depth 5}
 else{Test-OfflinePayloadManifest -PayloadRoot $PayloadRoot -ExpectedApplicationVersion $ApplicationVersion|ConvertTo-Json -Depth 5}
}
