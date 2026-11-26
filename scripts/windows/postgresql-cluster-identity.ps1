# Shared fail-closed state and ownership checks for the PostgreSQL data
# directory. These helpers only read state or delegate to the native
# provisioner's --verify-data mode; they never create, modify or adopt a
# cluster by path. Every ambiguous condition throws before provisioning or
# database bootstrap can run.

function Get-PostgreSqlClusterState {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$DataRoot)
 $data=[IO.Path]::GetFullPath($DataRoot)
 $item=Get-Item -LiteralPath $data -Force -ErrorAction SilentlyContinue
 if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "PostgreSQL data root must not be a reparse point."}
 $versionFile=Join-Path $data "PG_VERSION"
 if(-not(Test-Path -LiteralPath $versionFile -PathType Leaf)){
  if($null -ne $item){
   $children=@(Get-ChildItem -LiteralPath $data -Force -ErrorAction Stop)
   if($children.Count -gt 0){throw "PostgreSQL data directory exists without a recognized cluster; refusing to adopt it."}
  }
  return [pscustomobject]@{state="missing";initialized=$false;dataRoot=$data}
 }
 $versionItem=Get-Item -LiteralPath $versionFile -Force
 if(($versionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "PostgreSQL PG_VERSION must not be a reparse point."}
 $version=(Get-Content -LiteralPath $versionFile -Raw).Trim()
 if($version -cne "18"){throw "PostgreSQL data directory major version must be 18."}
 return [pscustomobject]@{state="initialized";initialized=$true;dataRoot=$data}
}

function Assert-PostgreSqlClusterInitialized {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$DataRoot)
 $state=Get-PostgreSqlClusterState -DataRoot $DataRoot
 if(-not $state.initialized){throw "PostgreSQL cluster is not initialized at the expected data directory; refusing database bootstrap."}
 $confPath=Join-Path $state.dataRoot "postgresql.conf"
 $hbaPath=Join-Path $state.dataRoot "pg_hba.conf"
 foreach($path in @($confPath,$hbaPath)){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "PostgreSQL cluster configuration file is missing; refusing database bootstrap."}
  $fileItem=Get-Item -LiteralPath $path -Force
  if(($fileItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "PostgreSQL cluster configuration file must not be a reparse point."}
 }
 $conf=Get-Content -LiteralPath $confPath -Raw
 if($conf -notmatch "(?m)^\s*listen_addresses\s*=\s*'127\.0\.0\.1'" -or $conf -notmatch "(?m)^\s*port\s*=\s*5432\s*$"){throw "PostgreSQL cluster must bind only to 127.0.0.1:5432; refusing database bootstrap."}
 $hba=Get-Content -LiteralPath $hbaPath -Raw
 if($hba -notmatch "127\.0\.0\.1/32\s+scram-sha-256" -or $hba -notmatch "0\.0\.0\.0/0\s+reject" -or $hba -notmatch "::/0\s+reject"){throw "PostgreSQL cluster authentication policy must be loopback-only SCRAM with explicit remote rejection; refusing database bootstrap."}
 [pscustomobject]@{valid=$true;dataRoot=$state.dataRoot;postgresMajorVersion="18";listenAddress="127.0.0.1";port=5432}
}

function Resolve-PostgreSqlServiceSid {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$ServiceName)
 if($ServiceName -cnotmatch '^EnterpriseIT[A-Za-z]+$'){throw "Unexpected Windows service name for PostgreSQL ownership verification."}
 try{$sid=([Security.Principal.NTAccount]("NT SERVICE\"+$ServiceName)).Translate([Security.Principal.SecurityIdentifier])}catch{throw "PostgreSQL service identity could not be resolved for ownership verification."}
 $value=$sid.Value
 if($value -notmatch '^S-1-5-80-(?:\d+-){4}\d+$'){throw "PostgreSQL service identity is invalid for ownership verification."}
 return $value
}

function Invoke-PostgreSqlClusterOwnershipVerify {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory=$true)][string]$BootstrapExe,
  [Parameter(Mandatory=$true)][string]$BootstrapSid,
  [Parameter(Mandatory=$true)][string]$PostgresSid,
  [string]$PgVersion="18",
  [string]$ProgramDataRoot=""
 )
 if(-not(Test-Path -LiteralPath $BootstrapExe -PathType Leaf)){throw "PostgreSQL ownership verification executable is missing."}
 $arguments=@("--verify-data","--bootstrap-sid",$BootstrapSid,"--postgres-sid",$PostgresSid,"--pg-version",$PgVersion)
 if(-not [string]::IsNullOrWhiteSpace($ProgramDataRoot)){$arguments+=@("--program-data-root",$ProgramDataRoot)}
 & $BootstrapExe @arguments|Out-Null
 if($LASTEXITCODE -ne 0){throw "PostgreSQL cluster ownership verification failed; refusing to adopt the existing data directory."}
 [pscustomobject]@{verified=$true;pgVersion=$PgVersion}
}
