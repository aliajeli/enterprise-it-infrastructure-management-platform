[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param([Parameter(Mandatory=$true)][string]$InstallRoot,[string]$DataRoot=(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data"),[Parameter(Mandatory=$true)][Security.SecureString]$SuperuserPassword)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$root=[IO.Path]::GetFullPath($InstallRoot)
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path (Join-Path $root "postgresql\pgsql\bin\initdb.exe"))){throw "PostgreSQL 18.7 binaries are not staged beneath versioned Program Files."}
$data=[IO.Path]::GetFullPath($DataRoot)
$pd=[IO.Path]::GetFullPath((Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18")).TrimEnd([IO.Path]::DirectorySeparatorChar)
if(-not $data.StartsWith(($pd+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or -not $data.EndsWith("\data",[StringComparison]::OrdinalIgnoreCase)){throw "Data directory must be ProgramData\EnterpriseIT\PostgreSQL\18\data."}
if($SuperuserPassword.Length -lt 16){throw "Bootstrap superuser password must be at least 16 characters."}
if($WhatIfPreference){[pscustomobject]@{dataRoot=$data;version="18";dryRun=$true;serviceStarted=$false}|ConvertTo-Json;return}
# Previous implementation wrote the bootstrap secret to a plaintext file.
# Even with a protected ACL that violates the owner policy. Fail before any
# filesystem, SCM, or database mutation until a reviewed transport is integrated.
throw "PostgreSQL initialization is disabled pending approved non-file credential transport and Windows acceptance."
