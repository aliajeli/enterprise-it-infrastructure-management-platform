# Disposable experiment only. NOT connected to installation or production.
# Inherited anonymous stdin may reach initdb's restricted re-exec; its security
# against same-user process/handle attacks has NOT been reviewed.
function Invoke-ExperimentalInitDbStdin {
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
 if(-not $IsWindows){throw 'Experimental initdb stdin is Windows-only.'}
 if(-not [IO.Path]::IsPathFullyQualified($Executable) -or -not(Test-Path -LiteralPath $Executable -PathType Leaf)){throw 'Invalid initdb executable.'}
 if(-not [IO.Path]::IsPathFullyQualified($DataPath)){throw 'Invalid initdb data path.'}
 if($Password.Length -lt 16 -or $Password.Length -gt 1024){throw 'Invalid initdb password length.'}
 $process=$null;$bytes=$null;$ptr=[IntPtr]::Zero;$plain=$null;$stage='credential-preparation'
 try{
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
  $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  if($plain.IndexOfAny([char[]]@([char]0,[char]10,[char]13)) -ge 0){throw 'Invalid password characters.'}
  # simple_prompt asks twice. Both copies travel only over anonymous stdin.
  $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($plain+"`n"+$plain+"`n")
  $plain=$null
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=$Executable
  foreach($a in $TestPrefixArguments){$psi.ArgumentList.Add($a)}
  foreach($a in @("--pgdata=$DataPath",'--username=platform_admin','--auth=scram-sha-256','--pwprompt','--encoding=UTF8')){$psi.ArgumentList.Add($a)}
  $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  # Never permit an inherited environment value to skip PostgreSQL re-exec.
  $null=$psi.Environment.Remove('PG_RESTRICT_EXEC')
  # PostgreSQL 18 simple_prompt deliberately falls back to stdin for msys.
  # Its restricted re-exec may acquire a console even when the initial
  # process was launched without one, so exercise that documented branch.
  # This override is process-local, contains no secret, and is experimental.
  $psi.Environment['OSTYPE']='msys'
  $psi.Environment['LC_ALL']='C'
  $stage='start-child'
  $process=[Diagnostics.Process]::Start($psi)
  # Consume but never forward either stream; an untrusted child may echo input.
  $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
  $stage='write-stdin'
  $cancel=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSeconds))
  try{$null=$process.StandardInput.BaseStream.WriteAsync($bytes,0,$bytes.Length,$cancel.Token).GetAwaiter().GetResult()}
  finally{$cancel.Dispose();$process.StandardInput.Close()}
  $stage='wait-child'
  if(-not $process.WaitForExit($TimeoutSeconds*1000)){throw 'Initdb process timed out.'}
  $null=$stdout.GetAwaiter().GetResult();$diagnostic=$stderr.GetAwaiter().GetResult()
  # Diagnostic defense only, NOT proof that the actual child token is safe.
  if($diagnostic -match '(?i)could not (?:create restricted token|re-execute with restricted token|start process for command)'){$stage='restricted-reexec-error';throw 'Restricted re-exec reported an error.'}
  if($process.ExitCode -ne 0){$stage='child-exit-'+$process.ExitCode;throw 'Initdb process failed.'}
  [pscustomobject]@{status='ok';transport='inherited-anonymous-stdin';plaintextFileCreated=$false}
 }catch{
  throw "Experimental initdb stdin operation failed at $stage."
 }finally{
  if($process){
   if(-not $process.HasExited){try{$process.Kill($true);$process.WaitForExit()}catch{}}
   $process.Dispose()
  }
  if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
  if($bytes){[Array]::Clear($bytes,0,$bytes.Length)}
  $plain=$null
 }
}
