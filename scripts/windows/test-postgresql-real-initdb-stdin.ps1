# Hosted-CI experiment with a disposable synthetic credential and data directory.
# This does not enable production initialization or establish Windows Server acceptance.
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $env:RUNNER_TEMP){throw 'This disposable experiment requires a Windows CI runner.'}
. (Join-Path $PSScriptRoot 'experimental-initdb-stdin.ps1')
$root=Join-Path $env:RUNNER_TEMP ('enterpriseit-real-initdb-stdin-'+[guid]::NewGuid().ToString('N'))
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
 $secret=ConvertTo-SecureString 'synthetic-real-initdb-stdin-password-48' -AsPlainText -Force
 $result=Invoke-ExperimentalInitDbStdin -Executable $initdb -DataPath $data -Password $secret -TimeoutSeconds 90
 if($result.status -ne 'ok' -or $result.plaintextFileCreated){throw 'Real initdb stdin experiment failed.'}
 if(-not(Test-Path -LiteralPath (Join-Path $data 'PG_VERSION') -PathType Leaf) -or (Get-Content -LiteralPath (Join-Path $data 'PG_VERSION') -Raw).Trim() -ne '18'){throw 'Disposable PostgreSQL 18 cluster was not initialized.'}
 $hba=Get-Content -LiteralPath (Join-Path $data 'pg_hba.conf') -Raw
 if($hba -notmatch 'scram-sha-256'){throw 'Disposable cluster did not use SCRAM authentication.'}
 # Start only a disposable loopback server. These credentials are synthetic;
 # the process-scoped PGPASSWORD is never written to a persistent environment,
 # command line, manifest or output. This tests authentication, not security
 # of production credential transport or clean Windows Server acceptance.
 $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
 try{$listener.Start();$port=([Net.IPEndPoint]$listener.LocalEndpoint).Port}finally{$listener.Stop()}
 $bindir=Split-Path $initdb -Parent
 $pgctl=Join-Path $bindir 'pg_ctl.exe';$psql=Join-Path $bindir 'psql.exe'
 $log=Join-Path $root 'postgres-test.log';$started=$false
 function Invoke-SyntheticTestProgram([string]$file,[string[]]$arguments,[string]$password,[bool]$needOutput=$false){
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$file
  foreach($a in $arguments){$start.ArgumentList.Add($a)}
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true
  $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  if($null -ne $password){$start.Environment['PGPASSWORD']=$password}else{$null=$start.Environment.Remove('PGPASSWORD')}
  $child=[Diagnostics.Process]::Start($start)
  try{
   $out=$child.StandardOutput.ReadToEndAsync();$err=$child.StandardError.ReadToEndAsync()
   if(-not $child.WaitForExit(60000)){try{$child.Kill($true)}catch{};throw 'Disposable PostgreSQL test process timed out.'}
   # pg_ctl descendants can retain its redirected handles. Do not wait for
   # EOF from those descendants after pg_ctl has exited. Only psql output is
   # required, and even that wait is bounded.
   $output=''
   if($needOutput){
    if(-not $out.Wait(5000)){throw 'Disposable test output did not close.'}
    $output=$out.GetAwaiter().GetResult()
   }
   return [pscustomobject]@{ExitCode=$child.ExitCode;Output=$output}
  }finally{$child.Dispose()}
 }
 try{
  Write-Output '::notice title=PostgreSQL stdin test::Starting disposable loopback server.'
  $server=Invoke-SyntheticTestProgram $pgctl @('-D',$data,'-l',$log,'-o',("-h 127.0.0.1 -p "+$port),'-w','start') $null
  if($server.ExitCode -ne 0){throw 'Disposable loopback PostgreSQL did not start.'}
  $started=$true
  $query=@('-X','-w','-h','127.0.0.1','-p',[string]$port,'-U','platform_admin','-d','postgres','-tAc','SELECT current_user')
  Write-Output '::notice title=PostgreSQL stdin test::Checking synthetic SCRAM authentication.'
  $accepted=Invoke-SyntheticTestProgram $psql $query 'synthetic-real-initdb-stdin-password-48' $true
  if($accepted.ExitCode -ne 0 -or $accepted.Output.Trim() -cne 'platform_admin'){throw 'Synthetic SCRAM authentication with the chosen password failed.'}
  $rejected=Invoke-SyntheticTestProgram $psql $query 'synthetic-incorrect-password-49'
  if($rejected.ExitCode -eq 0){throw 'Disposable cluster accepted an incorrect password.'}
 }finally{
  if($started -or (Test-Path -LiteralPath (Join-Path $data 'postmaster.pid'))){
   $stopped=Invoke-SyntheticTestProgram $pgctl @('-D',$data,'-m','immediate','-w','stop') $null
   if($stopped.ExitCode -ne 0){throw 'Disposable PostgreSQL did not stop.'}
  }
 }
 Write-Host 'Real PostgreSQL initdb synthetic anonymous-stdin experiment passed; production initialization remains disabled.'
}finally{
 if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
