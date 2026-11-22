$ErrorActionPreference="Stop"
$scriptPath=Join-Path $PSScriptRoot "initialize-postgresql-cluster.ps1"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
$installRoot=Join-Path $pf "EnterpriseIT\1.2.3"
$initdb=Join-Path $installRoot "postgresql\pgsql\bin\initdb.exe"
$dataBase=Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18"
$testRoot=Join-Path $dataBase ("bootstrap-test-"+[guid]::NewGuid().ToString("N"))
$data=Join-Path $testRoot "data"
New-Item -ItemType Directory -Path (Split-Path -Parent $initdb) -Force|Out-Null
[IO.File]::WriteAllText($initdb,"fixture")
$secret=ConvertTo-SecureString "test-only-bootstrap-password-123" -AsPlainText -Force
try{
 $dry=& $scriptPath -InstallRoot $installRoot -DataRoot $data -SuperuserPassword $secret -WhatIf|ConvertFrom-Json
 if(-not $dry.dryRun -or $dry.serviceStarted -or (Test-Path $data)){throw "Bootstrap WhatIf must be read-only and must not create the data directory."}
 New-Item -ItemType Directory -Path $data -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $data "PG_VERSION"),"18")
 $rejected=$false
 try{& $scriptPath -InstallRoot $installRoot -DataRoot $data -SuperuserPassword $secret -Confirm:$false|Out-Null}catch{$rejected=$true}
 if(-not $rejected -or (Get-Content (Join-Path $data "PG_VERSION") -Raw).Trim() -ne "18"){throw "Existing PostgreSQL cluster must be rejected without modification."}
 Remove-Item -LiteralPath $data -Recurse -Force
 New-Item -ItemType Directory -Path $data -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $data "operator-sentinel.txt"),"preserve")
 $rejected=$false
 try{& $scriptPath -InstallRoot $installRoot -DataRoot $data -SuperuserPassword $secret -Confirm:$false|Out-Null}catch{$rejected=$true}
 if(-not $rejected -or -not(Test-Path (Join-Path $data "operator-sentinel.txt"))){throw "Non-empty PostgreSQL data directory must be rejected and preserved."}
 $short=ConvertTo-SecureString "short" -AsPlainText -Force
 $rejected=$false
 try{& $scriptPath -InstallRoot $installRoot -DataRoot $data -SuperuserPassword $short -WhatIf|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Weak bootstrap password must be rejected."}
 Write-Host "PostgreSQL cluster initialization guard tests passed."
}finally{
 if(Test-Path $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}
 if(Test-Path $installRoot){Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue}
}