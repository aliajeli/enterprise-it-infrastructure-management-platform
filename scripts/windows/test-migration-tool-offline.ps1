# Non-mutating Prisma CLI and schema validation using a disposable fake URL.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Root)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Invoke-SyntheticPrisma([string]$Root,[string[]]$Arguments){
 $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=Join-Path $Root 'runtime\node.exe'
 $start.ArgumentList.Add((Join-Path $Root 'migration-tool\node_modules\prisma\build\index.js'))
 foreach($arg in $Arguments){$start.ArgumentList.Add($arg)}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 # Synthetic non-production URL and offline-failure mirror, scoped only to
 # this validation process. No actual connection or migration is performed.
 $start.Environment['DATABASE_URL']='postgresql://fixture:fixture@127.0.0.1:9/fixture'
 $start.Environment['PRISMA_ENGINES_MIRROR']='http://127.0.0.1:9'
 $start.Environment['PRISMA_HIDE_UPDATE_MESSAGE']='1'
 $child=[Diagnostics.Process]::Start($start)
 try{
  $out=$child.StandardOutput.ReadToEndAsync();$err=$child.StandardError.ReadToEndAsync()
  if(-not $child.WaitForExit(60000)){try{$child.Kill($true);$child.WaitForExit()}catch{};throw 'Prisma validation timed out.'}
  if(-not $out.Wait(5000) -or -not $err.Wait(5000)){throw 'Prisma validation output did not close.'}
  if($child.ExitCode -ne 0){throw 'Offline Prisma tooling validation failed.'}
  return $out.GetAwaiter().GetResult()
 }finally{$child.Dispose()}
}
$version=Invoke-SyntheticPrisma $Root @('--version')
if($version -notmatch '(?m)prisma\s*:\s*7\.10\.1'){throw 'Staged Prisma CLI version is incorrect.'}
$config=Join-Path $Root 'migration-tool\prisma.config.ts'
$null=Invoke-SyntheticPrisma $Root @('validate','--config',$config)
Write-Host 'Pinned Prisma CLI and local schema validation passed; migrations remain disabled.'
