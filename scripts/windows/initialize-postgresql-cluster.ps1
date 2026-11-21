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
if(-not $PSCmdlet.ShouldProcess($data,"Initialize PostgreSQL 18 with SCRAM authentication")){return}
if(Test-Path (Join-Path $data "PG_VERSION")){throw "Cluster already exists; initialization will not overwrite it."}
if((Test-Path $data) -and @(Get-ChildItem $data -Force).Count -gt 0){throw "Data directory is not empty; refusing initialization."}
New-Item -ItemType Directory -Path $data -Force|Out-Null
$tempRoot=Join-Path $env:ProgramData "EnterpriseIT\Temp"
New-Item -ItemType Directory -Path $tempRoot -Force|Out-Null
$pwFile=Join-Path $tempRoot ("pg-initdb-"+[guid]::NewGuid().ToString("N")+".txt")
$ptr=[IntPtr]::Zero
$plain=$null
try{
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($SuperuserPassword)
 $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
 [IO.File]::WriteAllText($pwFile,$plain+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
 & icacls.exe $pwFile /inheritance:r /grant:r "*S-1-5-18:F" "*S-1-5-32-544:F"|Out-Null
 if($LASTEXITCODE -ne 0){throw "Could not protect temporary PostgreSQL password file."}
 $initdb=Join-Path $root "postgresql\pgsql\bin\initdb.exe"
 & $initdb "--pgdata=$data" "--username=platform_admin" "--auth=scram-sha-256" "--pwfile=$pwFile" "--encoding=UTF8"
 if($LASTEXITCODE -ne 0){throw "PostgreSQL initdb failed; inspect non-secret diagnostics."}
 [IO.File]::AppendAllText((Join-Path $data "postgresql.conf"),"`r`n# Enterprise IT managed listener policy`r`nlisten_addresses = '127.0.0.1'`r`nport = 5432`r`npassword_encryption = 'scram-sha-256'`r`nssl = off`r`n",[Text.UTF8Encoding]::new($false))
 $hba="# TYPE DATABASE USER ADDRESS METHOD`r
host all all 127.0.0.1/32 scram-sha-256`r
host all all ::1/128 scram-sha-256`r
host all all 0.0.0.0/0 reject`r
host all all ::/0 reject`r`n"
 [IO.File]::WriteAllText((Join-Path $data "pg_hba.conf"),$hba,[Text.UTF8Encoding]::new($false))
 if((Get-Content (Join-Path $data "PG_VERSION") -Raw).Trim() -ne "18"){throw "Unexpected PostgreSQL major version."}
 [pscustomobject]@{version="18.7";dataRoot=$data;authentication="SCRAM-SHA-256";listenAddress="127.0.0.1";port=5432;serviceStarted=$false}|ConvertTo-Json -Depth 3
}finally{
 if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 $plain=$null
 if(Test-Path $pwFile){Remove-Item $pwFile -Force}
}
