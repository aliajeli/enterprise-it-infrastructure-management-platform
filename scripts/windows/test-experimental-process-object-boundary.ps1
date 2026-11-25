# Synthetic hosted-CI process-object experiment. No initdb, stdin, marker or
# credential is used. This is NOT a deployment helper or security approval.
[CmdletBinding()]
param(
 [ValidateSet('probe','attacker')][string]$Mode='probe',
 [int]$TargetPid=0,
 [string]$ExpectedSid='',
 [switch]$EnableDebug
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows -or $env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP){throw 'Disposable Windows hosted CI is required.'}
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
public static class EnterpriseItProcessObjectExperiment {
 const uint TOKEN_ADJUST_PRIVILEGES=0x20, TOKEN_QUERY=0x8, SE_PRIVILEGE_ENABLED=2;
 const uint CREATE_NO_WINDOW=0x08000000, PROCESS_DUP_HANDLE=0x40, READ_CONTROL=0x20000;
 const uint OWNER_SECURITY_INFORMATION=1, DACL_SECURITY_INFORMATION=4;
 const uint WAIT_TIMEOUT=258;
 [StructLayout(LayoutKind.Sequential)] struct LUID { public uint LowPart; public int HighPart; }
 [StructLayout(LayoutKind.Sequential)] struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID Luid; public uint Attributes; }
 [StructLayout(LayoutKind.Sequential)] struct SECURITY_ATTRIBUTES { public int Length; public IntPtr Descriptor; public bool Inherit; }
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct STARTUPINFO {
  public int cb; public string reserved,desktop,title; public int x,y,xsize,ysize,xchars,ychars,fill,flags; public short show,reserved2; public IntPtr reservedPtr,stdIn,stdOut,stdErr;
 }
 [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr Process, Thread; public int ProcessId, ThreadId; }
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int id);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateProcess(IntPtr process,uint exitCode);
 [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint timeout);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetKernelObjectSecurity(IntPtr h,uint information,byte[] descriptor,uint length,out uint needed);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string app,StringBuilder cmd,ref SECURITY_ATTRIBUTES processAttributes,IntPtr threadAttributes,bool inherit,uint flags,IntPtr environment,string directory,ref STARTUPINFO startup,out PROCESS_INFORMATION info);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool LookupPrivilegeValue(string system,string name,out LUID luid);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr token,bool disable,ref TOKEN_PRIVILEGES state,int length,out TOKEN_PRIVILEGES previous,out int returned);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string sddl,uint revision,out IntPtr descriptor,out uint size);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
 static Win32Exception Error(string stage) { return new Win32Exception(Marshal.GetLastWin32Error(),stage); }
 static TOKEN_PRIVILEGES SetPrivilege(IntPtr token,string name,bool enabled) {
  LUID luid; if(!LookupPrivilegeValue(null,name,out luid)) throw Error("lookup-privilege");
  var state=new TOKEN_PRIVILEGES { PrivilegeCount=1,Luid=luid,Attributes=enabled ? SE_PRIVILEGE_ENABLED : 0 };
  TOKEN_PRIVILEGES old; int n;
  if(!AdjustTokenPrivileges(token,false,ref state,Marshal.SizeOf(typeof(TOKEN_PRIVILEGES)),out old,out n)) throw Error("adjust-privilege");
  int err=Marshal.GetLastWin32Error(); if(err!=0) throw new Win32Exception(err,"privilege-not-assigned");
  return old;
 }
 static void Restore(IntPtr token,TOKEN_PRIVILEGES old) {
  TOKEN_PRIVILEGES ignored; int n;
  if(!AdjustTokenPrivileges(token,false,ref old,0,out ignored,out n) || Marshal.GetLastWin32Error()!=0) throw Error("restore-privilege");
 }
 public static int Probe(int pid,bool enableDebug) {
  IntPtr token=IntPtr.Zero; TOKEN_PRIVILEGES old=new TOKEN_PRIVILEGES(); bool changed=false;
  try {
   if(!OpenProcessToken(GetCurrentProcess(),TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY,out token)) throw Error("open-token");
   old=SetPrivilege(token,"SeDebugPrivilege",enableDebug); changed=true;
   IntPtr process=OpenProcess(PROCESS_DUP_HANDLE,false,pid);
   if(process!=IntPtr.Zero) { CloseHandle(process); return 0; }
   if(Marshal.GetLastWin32Error()==5) return 21;
   throw Error("open-process");
  } finally { try { if(changed) Restore(token,old); } finally { if(token!=IntPtr.Zero) CloseHandle(token); } }
 }
 public sealed class Child : IDisposable {
  public int Pid { get; private set; } IntPtr handle;
  internal Child(int pid,IntPtr h) { Pid=pid; handle=h; }
  public void Dispose() {
   if(handle==IntPtr.Zero) return;
   IntPtr h=handle; handle=IntPtr.Zero;
   try {
    if(WaitForSingleObject(h,0)==WAIT_TIMEOUT && !TerminateProcess(h,1)) throw Error("terminate-child");
    if(WaitForSingleObject(h,10000)!=0) throw new InvalidOperationException("child-not-stopped");
   } finally { CloseHandle(h); }
  }
 }
 public static Child Start(string executable) {
  IntPtr token=IntPtr.Zero,descriptor=IntPtr.Zero; TOKEN_PRIVILEGES old=new TOKEN_PRIVILEGES(); bool changed=false; PROCESS_INFORMATION info=new PROCESS_INFORMATION();
  try {
   if(!OpenProcessToken(GetCurrentProcess(),TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY,out token)) throw Error("open-token");
   old=SetPrivilege(token,"SeRestorePrivilege",true); changed=true;
   uint size; if(!ConvertStringSecurityDescriptorToSecurityDescriptor("O:SYD:P(A;;0x00100000;;;SY)",1,out descriptor,out size)) throw Error("sddl");
   var sa=new SECURITY_ATTRIBUTES { Length=Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)),Descriptor=descriptor,Inherit=false };
   var startup=new STARTUPINFO { cb=Marshal.SizeOf(typeof(STARTUPINFO)) };
   var cmd=new StringBuilder("\""+executable+"\" -NoLogo -NoProfile -NonInteractive -Command \"Start-Sleep -Seconds 90\"");
   if(!CreateProcess(executable,cmd,ref sa,IntPtr.Zero,false,CREATE_NO_WINDOW,IntPtr.Zero,null,ref startup,out info)) throw Error("create-process");
   Restore(token,old); changed=false;
   CloseHandle(info.Thread); info.Thread=IntPtr.Zero;
   uint needed; GetKernelObjectSecurity(info.Process,OWNER_SECURITY_INFORMATION|DACL_SECURITY_INFORMATION,null,0,out needed);
   if(needed==0 || needed>65536) throw Error("security-descriptor-size");
   byte[] security=new byte[needed];
   if(!GetKernelObjectSecurity(info.Process,OWNER_SECURITY_INFORMATION|DACL_SECURITY_INFORMATION,security,needed,out needed)) throw Error("security-descriptor-read");
   var sd=new RawSecurityDescriptor(security,0);
   if(sd.Owner==null || sd.Owner.Value!="S-1-5-18" || (sd.ControlFlags & ControlFlags.DiscretionaryAclProtected)==0 || sd.DiscretionaryAcl==null || sd.DiscretionaryAcl.Count!=1) throw new InvalidOperationException("unexpected-process-policy");
   var ace=sd.DiscretionaryAcl[0] as CommonAce;
   if(ace==null || ace.AceQualifier!=AceQualifier.AccessAllowed || ace.AceFlags!=AceFlags.None || ace.SecurityIdentifier.Value!="S-1-5-18" || ace.AccessMask!=0x00100000) throw new InvalidOperationException("unexpected-process-ace");
   var child=new Child(info.ProcessId,info.Process); info.Process=IntPtr.Zero; return child;
  } finally {
   if(info.Process!=IntPtr.Zero) { TerminateProcess(info.Process,1); WaitForSingleObject(info.Process,10000); CloseHandle(info.Process); }
   if(info.Thread!=IntPtr.Zero) CloseHandle(info.Thread);
   if(descriptor!=IntPtr.Zero) LocalFree(descriptor);
   try { if(changed) Restore(token,old); } finally { if(token!=IntPtr.Zero) CloseHandle(token); }
  }
 }
}
'@
if($Mode -eq 'attacker'){
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{if($identity.User.Value -cne $ExpectedSid){exit 23}}finally{$identity.Dispose()}
 try{exit [EnterpriseItProcessObjectExperiment]::Probe($TargetPid,[bool]$EnableDebug)}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 24}
}
function Invoke-Attacker([int]$ProcessId,[string]$Sid,[bool]$DebugPrivilege){
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName=Join-Path $PSHOME 'pwsh.exe'
 foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-Mode','attacker','-TargetPid',[string]$ProcessId,'-ExpectedSid',$Sid)){$start.ArgumentList.Add($arg)}
 if($DebugPrivilege){$start.ArgumentList.Add('-EnableDebug')}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $process=[Diagnostics.Process]::Start($start)
 try{
  $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit(30000)){try{$process.Kill($true)}catch{};throw 'Attacker fixture timed out.'}
  $output=$out.GetAwaiter().GetResult();$errors=$err.GetAwaiter().GetResult()
  if($process.ExitCode -notin @(0,21)){
   # The child receives no secret or marker; bound diagnostics nonetheless.
   $diagnostic=($errors+' '+$output).Replace("`r",' ').Replace("`n",' ')
   if($diagnostic.Length -gt 500){$diagnostic=$diagnostic.Substring(0,500)}
   throw "Attacker fixture setup exit $($process.ExitCode): $diagnostic"
  }
  return $process.ExitCode
 }finally{$process.Dispose()}
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
try{$sid=$identity.User.Value}finally{$identity.Dispose()}
$child=$null;$baseline=$null
try{
 # A default-security child is the positive control for the same user and
 # explicitly disabled SeDebugPrivilege. It never handles a secret or marker.
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName=Join-Path $PSHOME 'pwsh.exe'
 foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 90')){$start.ArgumentList.Add($arg)}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $baseline=[Diagnostics.Process]::Start($start)
 $baselineResult=Invoke-Attacker $baseline.Id $sid $false
 if($baselineResult -ne 0){throw "Default process DACL positive control did not grant same-user access; result $baselineResult."}
 $child=[EnterpriseItProcessObjectExperiment]::Start((Join-Path $PSHOME 'pwsh.exe'))
 $plain=Invoke-Attacker $child.Pid $sid $false
 if($plain -ne 21){throw "Strict process DACL probe was not denied; fixed result $plain."}
 $debug=Invoke-Attacker $child.Pid $sid $true
 if($debug -ne 0){throw "Enabled debug privilege did not produce the expected result; fixed result $debug."}
 Write-Host 'Synthetic process DACL denied same-user access without enabled SeDebugPrivilege, but an elevated same-user process with SeDebugPrivilege obtained PROCESS_DUP_HANDLE. No credential, handle duplication, initdb or production transport was tested.'
}finally{
 try{if($null -ne $child){$child.Dispose()}}
 finally{if($null -ne $baseline){try{if(-not $baseline.HasExited){$baseline.Kill($true);if(-not $baseline.WaitForExit(10000)){throw 'Baseline fixture cleanup timed out.'}}}finally{$baseline.Dispose()}}}
}
