# Fast disposable Windows CI test of packaged migration dependencies; does not
# build a full archive or enable production bootstrap, migration or installation.
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $env:RUNNER_TEMP){throw 'This experiment requires a disposable Windows CI runner.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
$digits=([guid]::NewGuid().ToString('N') -replace '[^0-9]','')
if($digits.Length -lt 8){throw 'Could not allocate test version.'}
$root=Join-Path $pf ('EnterpriseIT\0.0.'+$digits)
$work=Join-Path $env:RUNNER_TEMP ('enterpriseit-migration-fast-'+[guid]::NewGuid().ToString('N'))
$created=$false
if(Test-Path -LiteralPath $root){throw 'Refusing to adopt an existing version directory.'}
try{
 New-Item -ItemType Directory -Path $work -ErrorAction Stop|Out-Null
 New-Item -ItemType Directory -Path $root -ErrorAction Stop|Out-Null;$created=$true
 $runtime=Split-Path (Get-Command node.exe -ErrorAction Stop).Source -Parent
 & (Join-Path $PSScriptRoot 'stage-node-runtime.ps1') -NodeRuntimeDirectory $runtime -InstallRoot $root -Confirm:$false|Out-Null
 & (Join-Path $PSScriptRoot 'stage-migration-tool.ps1') -SourceRoot $repo -InstallRoot $root -Confirm:$false|Out-Null
 New-Item -ItemType Directory -Path (Join-Path $root 'packages\database') -ErrorAction Stop|Out-Null
 Copy-Item -LiteralPath (Join-Path $repo 'packages\database\prisma') -Destination (Join-Path $root 'packages\database\prisma') -Recurse
 $url='https://get.enterprisedb.com/postgresql/postgresql-18.7-1-windows-x64-binaries.zip'
 $archive=Join-Path $work 'postgresql.zip';$checksum=Join-Path $work 'postgresql.sha256';$extract=Join-Path $work 'postgres-extract'
 Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
 Invoke-WebRequest -Uri ($url+'.sha256') -OutFile $checksum -UseBasicParsing
 $expected=[regex]::Match((Get-Content -LiteralPath $checksum -Raw),'(?i)\b[a-f0-9]{64}\b').Value
 if($expected.Length -ne 64 -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $expected){throw 'PostgreSQL synthetic test archive checksum mismatch.'}
 Expand-Archive -LiteralPath $archive -DestinationPath $extract
 $binaries=@(Get-ChildItem -LiteralPath $extract -Filter initdb.exe -File -Recurse)
 if($binaries.Count -ne 1){throw 'Expected exactly one PostgreSQL initdb.'}
 $postgresRoot=Split-Path (Split-Path $binaries[0].FullName -Parent) -Parent
 New-Item -ItemType Directory -Path (Join-Path $root 'postgresql') -ErrorAction Stop|Out-Null
 Copy-Item -LiteralPath $postgresRoot -Destination (Join-Path $root 'postgresql\pgsql') -Recurse
 & (Join-Path $PSScriptRoot 'test-postgresql-migration-disposable.ps1') -PayloadRoot $root -WorkRoot $work
}finally{
 $live=Test-Path -LiteralPath (Join-Path $work 'DO_NOT_DELETE_RUNNING_POSTGRES')
 if($created -and (Test-Path -LiteralPath $root) -and -not $live){
  $item=Get-Item -LiteralPath $root -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Refusing to remove a replaced test root.'}
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
 }
 if((Test-Path -LiteralPath $work) -and -not $live){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
}
