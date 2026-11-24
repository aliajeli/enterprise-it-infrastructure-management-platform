# Experimental transport primitive only. Not wired to deployment or enabled for
# real PostgreSQL until threat review and Windows Server acceptance are complete.
# Dot-source this file to run synthetic tests; no side effects occur on import.
function Invoke-ExperimentalInitDbPipe {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory=$true)][string]$Executable,
  [string[]]$TestPrefixArguments=@(),
  [Parameter(Mandatory=$true)][string]$DataPath,
  [Parameter(Mandatory=$true)][Security.SecureString]$Password,
  [ValidateRange(1,300)][int]$TimeoutSeconds=60
 )
 Set-StrictMode -Version Latest
 $ErrorActionPreference='Stop'
 if(-not $IsWindows){throw 'Experimental initdb pipe is Windows-only.'}
 if(-not [IO.Path]::IsPathFullyQualified($Executable) -or -not(Test-Path -LiteralPath $Executable -PathType Leaf)){throw 'Invalid initdb executable.'}
 if(-not [IO.Path]::IsPathFullyQualified($DataPath)){throw 'Invalid initdb data path.'}
 if($Password.Length -lt 16 -or $Password.Length -gt 1024){throw 'Invalid initdb password length.'}
 $pipe=$null;$process=$null;$bytes=$null;$ptr=[IntPtr]::Zero;$plain=$null
 $stage='credential-preparation'
 try{
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
  $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  if($plain.IndexOfAny([char[]]@([char]0,[char]10,[char]13)) -ge 0){throw 'Invalid initdb password characters.'}
  $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($plain+"`n")
  $plain=$null
  # The unpredictable, single-instance local pipe is restricted to the current
  # Windows user. The child inherits that same identity. No plaintext file or
  # persistent environment variable is created.
  $stage='create-pipe'
  $name='enterpriseit-initdb-'+[guid]::NewGuid().ToString('N')
  $options=[IO.Pipes.PipeOptions]::Asynchronous -bor [IO.Pipes.PipeOptions]::CurrentUserOnly
  $pipe=[IO.Pipes.NamedPipeServerStream]::new($name,[IO.Pipes.PipeDirection]::Out,1,[IO.Pipes.PipeTransmissionMode]::Byte,$options)
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=$Executable
  foreach($a in $TestPrefixArguments){$psi.ArgumentList.Add($a)}
  foreach($a in @("--pgdata=$DataPath",'--username=platform_admin','--auth=scram-sha-256',("--pwfile=\\.\pipe\"+$name),'--encoding=UTF8')){$psi.ArgumentList.Add($a)}
  $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $stage='start-child'
  $process=[Diagnostics.Process]::Start($psi)
  $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
  $connect=$pipe.WaitForConnectionAsync()
  $exit=$process.WaitForExitAsync()
  $timer=[Threading.Tasks.Task]::Delay([TimeSpan]::FromSeconds($TimeoutSeconds))
  $stage='await-client'
  $winner=[Threading.Tasks.Task]::WhenAny([Threading.Tasks.Task[]]@($connect,$exit,$timer)).GetAwaiter().GetResult()
  if(-not [object]::ReferenceEquals($winner,$connect)){
   if($process.HasExited){
    $stage='child-exited-before-client-'+$process.ExitCode
    # Emit only fixed categories, never the child output itself. No password
    # bytes have been sent at this point.
    $diagnostic=$stderr.GetAwaiter().GetResult()
    if($diagnostic -match '(?i)could not open file.+for reading'){$stage+='-pwfile-open'}
    elseif($diagnostic -match '(?i)restricted token|re-execute'){$stage+='-restricted-token'}
    elseif($diagnostic -match '(?i)not the same version|not found in the same directory'){$stage+='-backend-binary'}
    elseif($diagnostic -match '(?i)permission denied|access is denied'){$stage+='-permission'}
    elseif($diagnostic -match '(?i)could not find|could not access'){$stage+='-missing-input'}
    else{$stage+='-other'}
   }else{$stage='client-timeout'}
   throw 'Initdb pipe connection failed or timed out.'
  }
  $connect.GetAwaiter().GetResult()
  $stage='verify-client'
  # Same-user pipe ACL is insufficient by itself: another process under the
  # same account could connect first. Send no bytes until the client PID is
  # proven to be the exact child we started.
  if(-not ('EnterpriseItInitDbPipeNative' -as [type])){
   Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class EnterpriseItInitDbPipeNative {
 [DllImport("kernel32.dll", SetLastError=true)]
 [return: MarshalAs(UnmanagedType.Bool)]
 public static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint clientProcessId);
}
'@
  }
  [uint32]$clientPid=0
  if(-not [EnterpriseItInitDbPipeNative]::GetNamedPipeClientProcessId($pipe.SafePipeHandle,[ref]$clientPid) -or $clientPid -ne $process.Id){throw 'Unexpected initdb pipe client.'}
  $stage='write-pipe'
  $cancel=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSeconds))
  try{$pipe.WriteAsync($bytes,0,$bytes.Length,$cancel.Token).GetAwaiter().GetResult()}
  finally{$cancel.Dispose()}
  # Keep the server open until the child has read its line and exited; closing
  # immediately can discard buffered named-pipe data on Windows.
  $stage='wait-child'
  if(-not $process.WaitForExit($TimeoutSeconds*1000)){throw 'Initdb process timed out.'}
  # Child output is deliberately consumed but never logged, because a child can
  # echo credential material on an error path.
  $null=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
  if($process.ExitCode -ne 0){$stage='child-exit-'+$process.ExitCode;throw 'Initdb process failed.'}
  [pscustomobject]@{status='ok';transport='current-user-named-pipe';plaintextFileCreated=$false}
 }catch{
  # Do not print exception messages that may contain command lines or child output.
  throw "Experimental initdb pipe operation failed at $stage."
 }finally{
  if($pipe){$pipe.Dispose()}
  if($process){
   if(-not $process.HasExited){try{$process.Kill($true);$process.WaitForExit()}catch{}}
   $process.Dispose()
  }
  if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
  if($bytes){[Array]::Clear($bytes,0,$bytes.Length)}
  $plain=$null
 }
}
