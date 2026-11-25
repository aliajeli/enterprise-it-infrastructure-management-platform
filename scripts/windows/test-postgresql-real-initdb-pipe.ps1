# Hosted-CI experiment with a disposable synthetic credential and data directory.
# This does not enable production initialization or establish Windows Server acceptance.
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $env:RUNNER_TEMP){throw 'This disposable experiment requires a Windows CI runner.'}
. (Join-Path $PSScriptRoot 'experimental-initdb-pipe.ps1')
$root=Join-Path $env:RUNNER_TEMP ('enterpriseit-real-initdb-'+[guid]::NewGuid().ToString('N'))
$archive=Join-Path $root 'postgresql-18.7-1-windows-x64-binaries.zip'
$checksum=$archive+'.sha256'
$extract=Join-Path $root 'extract'
$data=Join-Path $root 'disposable-data'
New-Item -ItemType Directory -Path $root -ErrorAction Stop|Out-Null
try{
 $url='https://get.enterprisedb.com/postgresql/postgresql-18.7-1-windows-x64-binaries.zip'
 Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
 Invoke-WebRequest -Uri ($url+'.sha256') -OutFile $checksum -UseBasicParsing
 $expected=[regex]::Match((Get-Content -LiteralPath $checksum -Raw),'(?i)\b[a-f0-9]{64}\b').Value
 if($expected.Length -ne 64 -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $expected){throw 'PostgreSQL test binary checksum mismatch.'}
 Expand-Archive -LiteralPath $archive -DestinationPath $extract
 $binaries=@(Get-ChildItem -LiteralPath $extract -Filter initdb.exe -File -Recurse)
 if($binaries.Count -ne 1){throw 'Expected exactly one PostgreSQL initdb binary.'}
 $initdb=$binaries[0].FullName
 $version=(& $initdb --version 2>&1|Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $version -notmatch '^initdb \(PostgreSQL\) 18\.7(?:\s|$)'){throw 'Unexpected PostgreSQL initdb version.'}
 $secret=ConvertTo-SecureString 'synthetic-real-initdb-password-48' -AsPlainText -Force
 $expectedFailure='Experimental initdb pipe operation failed at verify-client-pid-mismatch-direct-same-image.'
 $observedFailure=$null
 try{
  $result=Invoke-ExperimentalInitDbPipe -Executable $initdb -DataPath $data -Password $secret -TimeoutSeconds 240
 }catch{
  $observedFailure=$_.Exception.Message
 }
 if($observedFailure -cne $expectedFailure){
  throw 'The initdb re-exec pipe diagnostic did not reach the expected fail-closed PID-mismatch guard.'
 }
 # PID plus executable path is not authentication. The expected result is to
 # reject PostgreSQL's re-exec child before SecureString materialization or pipe write.
 $versionFile=Join-Path $data 'PG_VERSION'
 if(Test-Path -LiteralPath $versionFile -PathType Leaf){
  throw 'A PostgreSQL cluster was created despite the rejected pipe client.'
 }
 Write-Host 'EXPECTED FAIL-CLOSED RESULT: PostgreSQL re-exec PID mismatch was rejected before credential materialization or pipe write. This transport is not production-enabled.'
}finally{
 if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
