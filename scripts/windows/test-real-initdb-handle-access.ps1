# Disposable CI-only diagnostic. This probes whether a same-user process can
# obtain PROCESS_DUP_HANDLE on PostgreSQL 18's actual restricted re-exec child
# while initdb waits for input. No password or input marker is sent. Access to
# the process is a risk indicator, not proof that a particular pipe was read;
# denial is not a proof of production isolation. Never enable production from it.
[CmdletBinding()]
param(
 [ValidateSet('probe','attacker')][string]$Mode='probe',
 [int]$VictimPid=0,
 [string]$InitDbPath,
 [string]$WorkRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $env:RUNNER_TEMP){throw 'This diagnostic requires a disposable Windows CI runner.'}
if($Mode -eq 'attacker'){
 if($VictimPid -le 0){exit 22}
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EnterpriseItRestrictedInitDbProbe {
 [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
 [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool CloseHandle(IntPtr handle);
}
'@
 $handle=[EnterpriseItRestrictedInitDbProbe]::OpenProcess(0x40,$false,$VictimPid)
 if($handle -eq [IntPtr]::Zero){
  if([Runtime.InteropServices.Marshal]::GetLastWin32Error() -eq 5){exit 21}
  exit 22
 }
 $null=[EnterpriseItRestrictedInitDbProbe]::CloseHandle($handle)
 exit 0
}
if([string]::IsNullOrWhiteSpace($InitDbPath) -or [string]::IsNullOrWhiteSpace($WorkRoot)){throw 'The diagnostic requires disposable initdb and work paths.'}
$initdb=[IO.Path]::GetFullPath($InitDbPath)
$work=[IO.Path]::GetFullPath($WorkRoot)
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar)
if(-not $initdb.StartsWith(($runner+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or
   -not $work.StartsWith(($runner+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or
   -not (Test-Path -LiteralPath $initdb -PathType Leaf)) {throw 'Diagnostic paths must be beneath RUNNER_TEMP.'}
$data=Join-Path $work 'restricted-child-probe-data'
if(Test-Path -LiteralPath $data){throw 'Refusing an existing diagnostic data path.'}
$start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$initdb
foreach($arg in @("--pgdata=$data",'--username=platform_admin','--auth=scram-sha-256','--pwprompt','--encoding=UTF8')){$start.ArgumentList.Add($arg)}
$start.UseShellExecute=$false;$start.CreateNoWindow=$true
$start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
$null=$start.Environment.Remove('PG_RESTRICT_EXEC')
$start.Environment['OSTYPE']='msys';$start.Environment['LC_ALL']='C'
$parent=$null;$attacker=$null;$child=$null
try{
 $parent=[Diagnostics.Process]::Start($start)
 $stdout=$parent.StandardOutput.ReadToEndAsync();$stderr=$parent.StandardError.ReadToEndAsync()
 $deadline=[DateTime]::UtcNow.AddSeconds(30)
 $found=$null
 do {
  if($parent.HasExited){throw 'Initial initdb process exited before the restricted child was observed.'}
  $children=@(Get-CimInstance -ClassName Win32_Process -Filter ("ParentProcessId = "+$parent.Id) | Where-Object {
   $_.Name -ieq 'initdb.exe' -and $_.ExecutablePath -and [string]::Equals([IO.Path]::GetFullPath($_.ExecutablePath),$initdb,[StringComparison]::OrdinalIgnoreCase)
  })
  if($children.Count -gt 1){throw 'Ambiguous initdb child process.'}
  if($children.Count -eq 1){$found=$children[0];break}
  Start-Sleep -Milliseconds 200
 } while([DateTime]::UtcNow -lt $deadline)
 if($null -eq $found){throw 'Restricted initdb re-exec child was not observed.'}
 $child=[Diagnostics.Process]::GetProcessById([int]$found.ProcessId)
 if($child.HasExited){throw 'Restricted initdb child exited before the probe.'}
 $creation=$child.StartTime.ToUniversalTime()
 # This is an independent same-user process, not the initdb parent process.
 $attackerStart=[Diagnostics.ProcessStartInfo]::new();$attackerStart.FileName=Join-Path $PSHOME 'pwsh.exe'
 foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-Mode','attacker','-VictimPid',[string]$child.Id)){$attackerStart.ArgumentList.Add($arg)}
 $attackerStart.UseShellExecute=$false;$attackerStart.CreateNoWindow=$true
 $attacker=[Diagnostics.Process]::Start($attackerStart)
 if(-not $attacker.WaitForExit(20000)){throw 'Restricted child access probe timed out.'}
 if($child.HasExited -or $child.StartTime.ToUniversalTime() -ne $creation -or $parent.HasExited){throw 'Restricted initdb child did not remain stable during the probe.'}
 if($attacker.ExitCode -eq 0){
  Write-Host 'DIAGNOSTIC FINDING: same-user PROCESS_DUP_HANDLE was granted on the real initdb re-exec child. No credential or input marker was sent; this does not test the distinct Standard User versus service-account boundary.'
 }elseif($attacker.ExitCode -eq 21){
  Write-Host 'DIAGNOSTIC: same-user PROCESS_DUP_HANDLE was denied on the real initdb re-exec child.'
 }else{
  throw 'Restricted child access probe returned an unexpected result.'
 }
}finally{
 $cleanupFailed=$false
 if($attacker){
  try{if(-not $attacker.HasExited){$attacker.Kill($true);if(-not $attacker.WaitForExit(10000)){$cleanupFailed=$true}}}catch{$cleanupFailed=$true}
  $attacker.Dispose()
 }
 # Also stop the retained child if the parent exited unexpectedly or a tree
 # kill failed. If anything cannot be stopped, retain the disposable fixture.
 if($parent){
  try{if(-not $parent.HasExited){$parent.Kill($true);if(-not $parent.WaitForExit(10000)){$cleanupFailed=$true}}}catch{$cleanupFailed=$true}
 }
 if($child){
  try{if(-not $child.HasExited){$child.Kill($true);if(-not $child.WaitForExit(10000)){$cleanupFailed=$true}}}catch{$cleanupFailed=$true}
  $child.Dispose()
 }
 if($parent){$parent.Dispose()}
 if($cleanupFailed){
  [IO.File]::WriteAllText((Join-Path $work 'DO_NOT_DELETE_RUNNING_INITDB'),'Disposable initdb cleanup could not be confirmed.')
  throw 'Disposable initdb cleanup could not be confirmed.'
 }
}
