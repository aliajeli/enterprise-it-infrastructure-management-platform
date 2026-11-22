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
# Restrict the empty data directory before initdb writes cluster metadata or credentials.
& icacls.exe $data /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" /setowner "*S-1-5-18"|Out-Null
if($LASTEXITCODE -ne 0){throw "Could not establish the PostgreSQL data-directory security descriptor."}
$dataAcl=Get-Acl -LiteralPath $data
$dataRules=@($dataAcl.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier]))
$dataSids=@($dataRules|ForEach-Object{$_.IdentityReference.Value}|Sort-Object -Unique)
if(-not $dataAcl.AreAccessRulesProtected -or $dataSids.Count -ne 2 -or @($dataSids|Where-Object{$_ -notin @("S-1-5-18","S-1-5-32-544")}).Count -gt 0){throw "PostgreSQL data-directory ACL is not restricted to SYSTEM and Administrators."}
$tempRoot=Join-Path $env:ProgramData "EnterpriseIT\Temp"
New-Item -ItemType Directory -Path $tempRoot -Force|Out-Null
$tempWorkspace=Join-Path $tempRoot ("pg-initdb-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempWorkspace -ErrorAction Stop|Out-Null
$pwFile=Join-Path $tempWorkspace "password.txt"
$ptr=[IntPtr]::Zero
$plain=$null
try{
 # The directory DACL is established and checked before the secret file is created.
 & icacls.exe $tempWorkspace /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" /setowner "*S-1-5-18"|Out-Null
 if($LASTEXITCODE -ne 0){throw "Could not protect the PostgreSQL bootstrap workspace."}
 $workspaceAcl=Get-Acl -LiteralPath $tempWorkspace
 $workspaceRules=@($workspaceAcl.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier]))
 $workspaceSids=@($workspaceRules|ForEach-Object{$_.IdentityReference.Value}|Sort-Object -Unique)
 if(-not $workspaceAcl.AreAccessRulesProtected -or $workspaceSids.Count -ne 2 -or @($workspaceSids|Where-Object{$_ -notin @("S-1-5-18","S-1-5-32-544")}).Count -gt 0){throw "PostgreSQL bootstrap workspace ACL is not restricted to SYSTEM and Administrators."}
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($SuperuserPassword)
 $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
 [IO.File]::WriteAllText($pwFile,$plain+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
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
 if(Test-Path $tempWorkspace){Remove-Item $tempWorkspace -Recurse -Force}
}
