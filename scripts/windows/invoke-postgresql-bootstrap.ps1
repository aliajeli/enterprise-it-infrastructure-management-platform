[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][Security.SecureString]$SuperuserPassword,
 [ValidateRange(16,1024)][int]$MinimumPasswordLength=16
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
if(-not $IsWindows){throw "PostgreSQL bootstrap is Windows-only."}
if($SuperuserPassword.Length -lt $MinimumPasswordLength -or $SuperuserPassword.Length -gt 1024){throw "Bootstrap password length is invalid."}
$serviceName="EnterpriseITPostgreSQLBootstrap"
$pipeName="EnterpriseIT.PostgreSQL.Bootstrap.v1"
$service=Get-Service -Name $serviceName -ErrorAction Stop
$startedHere=$false
$ptr=[IntPtr]::Zero;$chars=$null;$bytes=$null;$frame=$null
try{
 if($service.Status -ne "Running"){
  Start-Service -Name $serviceName
  $startedHere=$true
  (Get-Service -Name $serviceName).WaitForStatus("Running",[TimeSpan]::FromSeconds(30))
 }
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($SuperuserPassword)
 $chars=[char[]]::new($SuperuserPassword.Length)
 [Runtime.InteropServices.Marshal]::Copy($ptr,$chars,0,$chars.Length)
 if([Array]::IndexOf($chars,[char]0) -ge 0 -or [Array]::IndexOf($chars,[char]10) -ge 0 -or [Array]::IndexOf($chars,[char]13) -ge 0){throw "Bootstrap password contains unsupported characters."}
 $encoding=[Text.UTF8Encoding]::new($false,$true)
 $bytes=$encoding.GetBytes($chars)
 if($bytes.Length -lt 16 -or $bytes.Length -gt 4096){throw "Bootstrap password byte length is invalid."}
 $frame=[byte[]]::new(4+$bytes.Length)
 $prefix=[BitConverter]::GetBytes([int]$bytes.Length)
 [Array]::Reverse($prefix)
 [Array]::Copy($prefix,0,$frame,0,4)
 [Array]::Copy($bytes,0,$frame,4,$bytes.Length)
 $client=[IO.Pipes.NamedPipeClientStream]::new(".", $pipeName, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::None, [Security.Principal.TokenImpersonationLevel]::Impersonation)
 try{
  $client.Connect(30000)
  $client.Write($frame,0,$frame.Length)
  $client.Flush()
  $status=$client.ReadByte()
  if($status -ne 0){throw "PostgreSQL bootstrap service rejected or failed the request. No credential details were returned."}
 }finally{$client.Dispose()}
 [pscustomobject]@{status="initialized";service=$serviceName;credentialTransport="restricted-local-named-pipe";plaintextFileCreated=$false;serviceStopped=$startedHere}|ConvertTo-Json -Depth 3
}finally{
 if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 if($chars){[Array]::Clear($chars,0,$chars.Length)}
 if($bytes){[Array]::Clear($bytes,0,$bytes.Length)}
 if($frame){[Array]::Clear($frame,0,$frame.Length)}
 if($startedHere){
  try{Stop-Service -Name $serviceName -ErrorAction Stop; (Get-Service -Name $serviceName).WaitForStatus("Stopped",[TimeSpan]::FromSeconds(30))}catch{throw "Bootstrap service could not be stopped cleanly."}
 }
}
