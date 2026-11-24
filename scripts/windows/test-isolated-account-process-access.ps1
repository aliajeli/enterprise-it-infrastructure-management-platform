# Disposable hosted-CI diagnostic only. It creates an unprivileged, random,
# expiring LOCAL test account and deletes it after probing process access. It
# never handles a PostgreSQL credential, enables a deployment path, or asserts
# that a compromised administrator or the test account itself is isolated.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows -or $env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP){throw 'This fixture requires a disposable GitHub-hosted Windows runner.'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
try{
 if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'An elevated disposable runner is required.'}
 $callerSid=$identity.User.Value
}finally{$identity.Dispose()}
$name='eip'+[guid]::NewGuid().ToString('N').Substring(0,12)
$random=[byte[]]::new(32)
[Security.Cryptography.RandomNumberGenerator]::Fill($random)
$synthetic=[Convert]::ToBase64String($random)+'aA1!'
[Array]::Clear($random,0,$random.Length)
$password=ConvertTo-SecureString $synthetic -AsPlainText -Force
$synthetic=$null
$accountSid=$null;$created=$false;$victim=$null;$attacker=$null;$peer=$null;$stage='create-account'
function Start-FixtureProcess([string]$Code,[bool]$UseIsolatedAccount){
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName=Join-Path $PSHOME 'pwsh.exe'
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
 foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded)){$start.ArgumentList.Add($arg)}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 if($UseIsolatedAccount){$start.Domain=$env:COMPUTERNAME;$start.UserName=$name;$start.Password=$password;$start.LoadUserProfile=$false}
 return [Diagnostics.Process]::Start($start)
}
function Stop-FixtureProcess([Diagnostics.Process]$Process){
 if($null -eq $Process){return}
 try{if(-not $Process.HasExited){$Process.Kill($true);if(-not $Process.WaitForExit(10000)){throw 'Fixture process did not exit.'}}}finally{$Process.Dispose()}
}
try{
 # New-LocalUser creates the account atomically; never adopt an existing name.
 # The expiring account is only a synthetic CI fixture, not a service identity.
 $account=New-LocalUser -Name $name -Password $password -AccountExpires ([DateTime]::Now.AddHours(2)) -Description 'Disposable Enterprise IT CI isolation fixture' -ErrorAction Stop
 $created=$true;$accountSid=$account.SID.Value
 if([string]::IsNullOrWhiteSpace($accountSid)){throw 'Fixture account SID was not available.'}
 $victimCode=@'
$ErrorActionPreference='Stop'
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
try {
 $admin=([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 [Console]::Out.WriteLine($id.User.Value+'|'+$admin);[Console]::Out.Flush()
 Start-Sleep -Seconds 120
}finally{$id.Dispose()}
'@
 $stage='start-victim'
 $victim=Start-FixtureProcess $victimCode $true
 $stderr=$victim.StandardError.ReadToEndAsync()
 $lineTask=$victim.StandardOutput.ReadLineAsync()
 if(-not $lineTask.Wait(20000)){throw 'Isolated fixture process did not report readiness.'}
 $line=$lineTask.GetAwaiter().GetResult();$parts=@($line -split '\|')
 if($parts.Count -ne 2 -or $parts[0] -cne $accountSid -or $parts[1] -cne 'False'){throw 'Fixture victim did not run as the intended non-admin identity.'}
 if($victim.HasExited){throw 'Fixture victim exited before the process-access probe.'}
 # The probe asks only for PROCESS_DUP_HANDLE. It sends no marker or secret.
 # Access from the installer identity is a risk; denial alone proves no security.
 $probeCode=@'
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FixtureProcessProbe {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
 [DllImport("kernel32.dll")] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool CloseHandle(IntPtr handle);
}
"@
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
try{if($id.User.Value -cne '__EXPECTED_SID__'){exit 23}}finally{$id.Dispose()}
$h=[FixtureProcessProbe]::OpenProcess(0x40,$false,__VICTIM_PID__)
if($h -eq [IntPtr]::Zero){if([Runtime.InteropServices.Marshal]::GetLastWin32Error() -eq 5){exit 21};exit 22}
$null=[FixtureProcessProbe]::CloseHandle($h)
exit 0
'@
 $probeCode=$probeCode.Replace('__VICTIM_PID__',[string]$victim.Id)
 $stage='caller-access-probe'
 $attacker=Start-FixtureProcess ($probeCode.Replace('__EXPECTED_SID__',$callerSid)) $false
 $attackerErr=$attacker.StandardError.ReadToEndAsync()
 if(-not $attacker.WaitForExit(30000)){$stage='caller-timeout';throw 'Caller-identity probe timed out.'}
 if($victim.HasExited){throw 'Fixture victim exited before caller probe finished.'}
 $callerExit=$attacker.ExitCode
 # Positive control: a second process under the isolated identity should be
 # able to obtain the right, demonstrating that this does not defend against
 # a compromised process using that same identity.
 $stage='start-peer'
 $peer=Start-FixtureProcess ($probeCode.Replace('__EXPECTED_SID__',$accountSid)) $true
 $peerErr=$peer.StandardError.ReadToEndAsync()
 if(-not $peer.WaitForExit(30000)){$stage='peer-timeout';throw 'Same-isolated-user control timed out.'}
 if($victim.HasExited){$stage='victim-exited-before-peer';throw 'Fixture victim exited during the control.'}
 if($peer.ExitCode -ne 0){
  $stage='peer-exit-'+$peer.ExitCode
  # Classify only fixed error categories, never emit child diagnostics.
  if($peerErr.Wait(5000)){
   $diagnostic=$peerErr.GetAwaiter().GetResult()
   if($diagnostic -match '(?i)access.*denied|unauthorized'){$stage+='-access'}
   elseif($diagnostic -match '(?i)cannot find|not found|could not find'){$stage+='-missing'}
   elseif($diagnostic -match '(?i)compile|add-type'){$stage+='-compile'}
  }
  throw 'Same-isolated-user control did not obtain process access.'
 }
 if($callerExit -eq 0){$stage='caller-access-granted';throw 'Caller identity obtained access.'}
 if($callerExit -ne 21){throw 'Caller-identity probe returned an unexpected result.'}
 Write-Host 'Different-identity access was denied, while the same-isolated-user control succeeded. This is not production security approval.'
}catch{
 # Exceptions from process/account APIs are deliberately not emitted; their
 # text is not a safe channel for credential-adjacent diagnostics.
 throw "Isolated account probe failed at $stage."
}finally{
 $cleanupFailed=$false
 foreach($process in @($peer,$attacker,$victim)){
  if($null -ne $process){try{Stop-FixtureProcess $process}catch{$cleanupFailed=$true}}
 }
 if($created){
  try{
   $current=Get-LocalUser -Name $name -ErrorAction Stop
   if($current.SID.Value -cne $accountSid){throw 'Fixture account identity changed.'}
   Remove-LocalUser -SID $current.SID -ErrorAction Stop
  }catch{$cleanupFailed=$true}
 }
 if($password){$password.Dispose()}
 if($cleanupFailed){throw 'Isolated account fixture cleanup could not be confirmed.'}
}
