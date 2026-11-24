# Hosted-CI wrapper for a no-credential access probe of the actual initdb child.
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $env:RUNNER_TEMP){throw 'This diagnostic requires a disposable Windows CI runner.'}
$root=Join-Path $env:RUNNER_TEMP ('enterpriseit-initdb-access-'+[guid]::NewGuid().ToString('N'))
$archive=Join-Path $root 'postgresql.zip';$checksum=Join-Path $root 'postgresql.sha256'
$extract=Join-Path $root 'extract'
New-Item -ItemType Directory -Path $root -ErrorAction Stop|Out-Null
try{
 $url='https://get.enterprisedb.com/postgresql/postgresql-18.7-1-windows-x64-binaries.zip'
 Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
 Invoke-WebRequest -Uri ($url+'.sha256') -OutFile $checksum -UseBasicParsing
 $expected=[regex]::Match((Get-Content -LiteralPath $checksum -Raw),'(?i)\b[a-f0-9]{64}\b').Value
 if($expected.Length -ne 64 -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $expected){throw 'PostgreSQL diagnostic archive checksum mismatch.'}
 Expand-Archive -LiteralPath $archive -DestinationPath $extract
 $binaries=@(Get-ChildItem -LiteralPath $extract -Filter initdb.exe -File -Recurse)
 if($binaries.Count -ne 1){throw 'Expected exactly one PostgreSQL initdb diagnostic binary.'}
 $version=(& $binaries[0].FullName --version 2>&1|Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $version -notmatch '^initdb \(PostgreSQL\) 18\.7(?:\s|$)'){throw 'Unexpected PostgreSQL initdb version.'}
 & (Join-Path $PSScriptRoot 'test-real-initdb-handle-access.ps1') -InitDbPath $binaries[0].FullName -WorkRoot $root
}finally{
 if((Test-Path -LiteralPath $root) -and -not (Test-Path -LiteralPath (Join-Path $root 'DO_NOT_DELETE_RUNNING_INITDB'))){
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
 }
}
