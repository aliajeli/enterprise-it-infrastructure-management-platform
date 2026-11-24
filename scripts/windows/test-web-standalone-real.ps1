# Real Next.js build staging smoke on an isolated Windows CI runner. No SCM
# service is installed and this is not Windows Server installer acceptance.
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $env:RUNNER_TEMP){throw 'This test requires a Windows CI runner.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$source=Join-Path $repo 'apps\web\.next\standalone'
$root=Join-Path $env:RUNNER_TEMP ('enterpriseit-real-web-'+[guid]::NewGuid().ToString('N'))
$node=(Get-Command node.exe -ErrorAction Stop).Source
$api=$null;$web=$null
function Start-TestNode([string]$script){
 $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$node
 $start.ArgumentList.Add($script);$start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $child=[Diagnostics.Process]::Start($start)
 # Consume streams asynchronously without displaying child output.
 $null=$child.StandardOutput.ReadToEndAsync();$null=$child.StandardError.ReadToEndAsync()
 return $child
}
function Get-TestHttp([string]$url,[Diagnostics.Process]$child){
 $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(3)
 try{
  $deadline=[DateTime]::UtcNow.AddSeconds(45)
  while([DateTime]::UtcNow -lt $deadline){
   if($child.HasExited){throw 'A disposable Web test process exited before readiness.'}
   try{return $client.GetAsync($url).GetAwaiter().GetResult()}catch{Start-Sleep -Milliseconds 300}
  }
  throw 'Disposable Web endpoint did not become ready.'
 }finally{$client.Dispose()}
}
try{
 # Check availability before starting loopback-only fixtures; no external or
 # wildcard listeners and no network/router configuration changes are made.
 foreach($port in @(13000,13001)){
  $check=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port)
  try{$check.Start()}finally{$check.Stop()}
 }
 New-Item -ItemType Directory -Path $root -ErrorAction Stop|Out-Null
 $result=& (Join-Path $PSScriptRoot 'stage-web-standalone.ps1') -StandaloneDirectory $source -InstallRoot $root -Confirm:$false | ConvertFrom-Json
 if($result.layout -ne 'monorepo'){throw 'Real Next.js build did not produce the expected monorepo layout.'}
 $api=Start-TestNode (Join-Path $PSScriptRoot 'test-fixture-web-api.cjs')
 $apiReady=Get-TestHttp 'http://127.0.0.1:13001/fixture-ready' $api
 try{if(-not $apiReady.IsSuccessStatusCode){throw 'Synthetic API fixture did not start.'}}finally{$apiReady.Dispose()}
 $web=Start-TestNode (Join-Path $root 'apps\web\.next\standalone\service-entry.cjs')
 $health=Get-TestHttp 'http://127.0.0.1:13000/health/ready' $web
 try{if(-not $health.IsSuccessStatusCode){throw 'Staged Web readiness failed.'}}finally{$health.Dispose()}
 $login=Get-TestHttp 'http://127.0.0.1:13000/login' $web
 try{
  if(-not $login.IsSuccessStatusCode -or $login.Headers.Contains('X-Powered-By')){throw 'Web response did not preserve its build-time security configuration.'}
 }finally{$login.Dispose()}
 $rewrite=Get-TestHttp 'http://127.0.0.1:13000/api/fixture-probe' $web
 try{
  $body=$rewrite.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
  if(-not $rewrite.IsSuccessStatusCode -or $body.fixture -ne 'enterpriseit-web-rewrite' -or $body.path -ne '/api/fixture-probe'){throw 'Staged Web API rewrite failed.'}
 }finally{$rewrite.Dispose()}
 Write-Host 'Real monorepo Web staging, readiness, security header and API rewrite tests passed; no installer or SCM services were created.'
}finally{
 foreach($child in @($web,$api)){
  if($child){
   if(-not $child.HasExited){
    try{$child.StandardInput.WriteLine('SHUTDOWN');$child.StandardInput.Close()}catch{}
    if(-not $child.WaitForExit(15000)){try{$child.Kill($true);$child.WaitForExit()}catch{}}
   }
   $child.Dispose()
  }
 }
 if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
