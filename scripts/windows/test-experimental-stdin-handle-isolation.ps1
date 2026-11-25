# Adversarial, synthetic-only diagnostic. Models a same-user process duplicating
# a directly launched child's inherited anonymous stdin handle. It deliberately
# does NOT claim to model PostgreSQL's restricted-token child or production.
[CmdletBinding()]
param(
 [ValidateSet('probe','victim','attacker')][string]$Mode='probe',
 [int]$VictimPid=0,
 [long]$InputHandle=0
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'This diagnostic requires Windows.'}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EnterpriseItStdinIsolationProbe {
 [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int nStdHandle);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
 [DllImport("kernel32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
 public static extern bool DuplicateHandle(IntPtr sourceProcess, IntPtr sourceHandle, IntPtr targetProcess, out IntPtr targetHandle, uint access, bool inherit, uint options);
 [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool CloseHandle(IntPtr handle);
}
'@
if($Mode -eq 'victim'){
 $handle=[EnterpriseItStdinIsolationProbe]::GetStdHandle(-10)
 if($handle -eq [IntPtr]::Zero -or $handle -eq [IntPtr](-1)){exit 41}
 [Console]::Out.WriteLine($handle.ToInt64());[Console]::Out.Flush()
 Start-Sleep -Seconds 60
 exit 42
}
if($Mode -eq 'attacker'){
 $source=[EnterpriseItStdinIsolationProbe]::OpenProcess(0x40,$false,$VictimPid)
 if($source -eq [IntPtr]::Zero){
  if([Runtime.InteropServices.Marshal]::GetLastWin32Error() -eq 5){[Console]::Out.WriteLine('DENIED');exit 21}
  [Console]::Out.WriteLine('ERROR');exit 22
 }
 try{
  $duplicate=[IntPtr]::Zero
  if(-not [EnterpriseItStdinIsolationProbe]::DuplicateHandle($source,[IntPtr]$InputHandle,[EnterpriseItStdinIsolationProbe]::GetCurrentProcess(),[ref]$duplicate,0,$false,2)){
   if([Runtime.InteropServices.Marshal]::GetLastWin32Error() -eq 5){[Console]::Out.WriteLine('DENIED');exit 21}
   [Console]::Out.WriteLine('ERROR');exit 23
  }
  $safe=[Microsoft.Win32.SafeHandles.SafeFileHandle]::new($duplicate,$true)
  $stream=[IO.FileStream]::new($safe,[IO.FileAccess]::Read)
  try{
   $reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true))
   try{
    [Console]::Out.WriteLine('READY');[Console]::Out.Flush()
    $value=$reader.ReadLine()
    if($value -ceq 'synthetic-stdin-isolation-marker-41'){exit 0}
    exit 24
   }finally{$reader.Dispose()}
  }finally{$stream.Dispose()}
 }finally{$null=[EnterpriseItStdinIsolationProbe]::CloseHandle($source)}
}
function New-ProbeProcess([string[]]$Arguments){
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName=Join-Path $PSHOME 'pwsh.exe'
 foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath)+$Arguments){$start.ArgumentList.Add($arg)}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 return [Diagnostics.Process]::Start($start)
}
function Read-ProbeLine([Diagnostics.Process]$Process){
 $task=$Process.StandardOutput.ReadLineAsync()
 if(-not $task.Wait(20000)){throw 'Synthetic isolation probe timed out waiting for readiness.'}
 return $task.GetAwaiter().GetResult()
}
$victim=$null;$attacker=$null
try{
 $victim=New-ProbeProcess @('-Mode','victim')
 $handleText=Read-ProbeLine $victim
 [long]$handleValue=0
 if(-not [long]::TryParse($handleText,[ref]$handleValue) -or $handleValue -le 0){throw 'Synthetic victim did not report a valid stdin handle.'}
 $attacker=New-ProbeProcess @('-Mode','attacker','-VictimPid',[string]$victim.Id,'-InputHandle',[string]$handleValue)
 $state=Read-ProbeLine $attacker
 if($state -eq 'DENIED'){
  if(-not $attacker.WaitForExit(10000) -or $attacker.ExitCode -ne 21){throw 'Synthetic probe denial was not confirmed.'}
  Write-Host 'DIAGNOSTIC: same-user PROCESS_DUP_HANDLE was denied for the synthetic child.'
  return
 }
 if($state -ne 'READY'){throw 'Synthetic attacker setup failed; probe result is indeterminate.'}
 # The victim never reads. If the attacker reads this marker, isolation failed.
 $victim.StandardInput.WriteLine('synthetic-stdin-isolation-marker-41')
 $victim.StandardInput.Flush()
 if(-not $attacker.WaitForExit(15000)){throw 'Synthetic attacker did not finish; isolation was not established.'}
 if($attacker.ExitCode -eq 0){
  Write-Host 'DIAGNOSTIC FINDING: a same-user process duplicated the synthetic child stdin handle and read the synthetic marker. This is outside the supported isolation boundary; no production credential was used.'
  return
 }
 throw 'Synthetic attacker returned an unexpected result; probe classification failed.'
}finally{
 foreach($child in @($attacker,$victim)){
  if($child){if(-not $child.HasExited){try{$child.Kill($true);$child.WaitForExit()}catch{}};$child.Dispose()}
 }
}
