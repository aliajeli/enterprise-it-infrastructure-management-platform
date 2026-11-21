[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param([Parameter(Mandatory=$true)][string]$InstallRoot,[string]$CacheDirectory=(Join-Path $env:ProgramData "EnterpriseIT\Downloads"))
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$archiveName="postgresql-18.7-1-windows-x64-binaries.zip"
$archiveUrl="https://get.enterprisedb.com/postgresql/$archiveName"
function Get-PostgreSqlStagePlan([string]$InstallRoot,[string]$CacheDirectory){
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
 if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be Program Files\EnterpriseIT\<major.minor.patch>."}
 [pscustomobject]@{Version="18.7";PackageRevision="1";ArchiveName=$archiveName;ArchiveUrl=$archiveUrl;ChecksumUrl=($archiveUrl+".sha256");InstallRoot=$root;Destination=(Join-Path $root "postgresql");CacheDirectory=[IO.Path]::GetFullPath($CacheDirectory)}
}
if($MyInvocation.InvocationName -ne "."){
 $p=Get-PostgreSqlStagePlan -InstallRoot $InstallRoot -CacheDirectory $CacheDirectory
 if($WhatIfPreference){[pscustomobject]@{version=$p.Version;destination=$p.Destination;dryRun=$true}|ConvertTo-Json;return}
 if(-not $PSCmdlet.ShouldProcess($p.Destination,"Download, verify and stage pinned PostgreSQL 18.7-1 Windows x64 binaries")){return}
 if(Test-Path -LiteralPath $p.Destination){throw "PostgreSQL destination exists; refusing to overwrite immutable payload."}
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 New-Item -ItemType Directory -Path $p.CacheDirectory -Force|Out-Null
 $archive=Join-Path $p.CacheDirectory $p.ArchiveName
 if(-not(Test-Path -LiteralPath $archive)){Invoke-WebRequest -Uri $p.ArchiveUrl -OutFile $archive -UseBasicParsing}
 $sidecar="$archive.sha256"
 Invoke-WebRequest -Uri $p.ChecksumUrl -OutFile $sidecar -UseBasicParsing
 $expected=[regex]::Match((Get-Content -LiteralPath $sidecar -Raw),'(?i)\b[a-f0-9]{64}\b').Value.ToLowerInvariant()
 if($expected.Length -ne 64){throw "EDB SHA-256 sidecar is invalid."}
 $actual=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
 if($actual -ne $expected){Remove-Item -LiteralPath $archive -Force;throw "PostgreSQL archive SHA-256 verification failed."}
 $temp=Join-Path $env:TEMP ("enterpriseit-pg-"+[guid]::NewGuid().ToString("N"))
 try{
  Expand-Archive -LiteralPath $archive -DestinationPath $temp -Force
  $roots=@(Get-ChildItem -LiteralPath $temp -Directory -Recurse|Where-Object{Test-Path (Join-Path $_.FullName "bin\postgres.exe")})
  if($roots.Count -ne 1){throw "Archive must contain exactly one PostgreSQL binary root."}
  $versionOutput=& (Join-Path $roots[0].FullName "bin\postgres.exe") --version
  if($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '^postgres \(PostgreSQL\) 18\.7(?:\s|$)'){throw "PostgreSQL binary version is not pinned 18.7."}
  New-Item -ItemType Directory -Path $p.Destination -Force|Out-Null
  Copy-Item -LiteralPath $roots[0].FullName -Destination (Join-Path $p.Destination "pgsql") -Recurse
  foreach($relative in @("bin\postgres.exe","bin\pg_ctl.exe","bin\initdb.exe","share\postgresql.conf.sample")){if(-not(Test-Path -LiteralPath (Join-Path $p.Destination ("pgsql\"+$relative)))){throw "PostgreSQL payload is incomplete: $relative"}}
  [pscustomobject]@{version="18.7";packageRevision="1";sha256=$actual;destination=$p.Destination;licensePayloadPreserved=$true}|ConvertTo-Json -Depth 3
 }catch{if(Test-Path -LiteralPath $p.Destination){Remove-Item -LiteralPath $p.Destination -Recurse -Force};throw}
 finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
}
