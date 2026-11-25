# The provisioner must work from the elevated runner account, not just LocalSystem.
# Place the disposable fixture directly below the OS ProgramData directory so
# the test exercises a production-like trusted ancestor chain, not runner TEMP ACLs.
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($identity.User.Value -eq 'S-1-5-18'){throw 'Administrator smoke must not run as LocalSystem.'}
$volumeRoot=[IO.Path]::GetPathRoot($env:SystemRoot)
if(-not $volumeRoot){throw 'Could not resolve the system volume root.'}
$smokeRoot=Join-Path $volumeRoot ('EnterpriseIT-Vault-Admin-Smoke-' + [guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $smokeRoot){throw 'Refusing to adopt an existing smoke-test directory.'}
$pd=Join-Path $smokeRoot 'ProgramData'
$acl=[Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true,$false)
foreach($sid in @('S-1-5-18','S-1-5-32-544')){
 $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
 $acl.AddAccessRule($rule)
}
$rootCreated=$false
try{
 # Create each fixture directory with its protected ACL at creation time.
 ([IO.DirectoryInfo]::new($smokeRoot)).Create($acl)
 $rootCreated=$true
 ([IO.DirectoryInfo]::new($pd)).Create($acl)
 $sidText=(& sc.exe showsid EnterpriseITApi 2>&1|Out-String)
 if($LASTEXITCODE -ne 0){throw 'Could not resolve API service SID.'}
 $match=[regex]::Match($sidText,'S-1-5-80-(?:\d+-){4}\d+')
 if(-not $match.Success){throw 'Could not resolve API service SID.'}
 $helper=Join-Path $PSScriptRoot '..\..\apps\api\windows\keyring-storage-helper\bin\Release\net10.0-windows\CredentialVault.KeyringStorageHelper.exe'
 $attempt=0
 foreach($mode in @('--provision-vault','--verify-vault','--provision-vault')){
  $attempt++
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=[IO.Path]::GetFullPath($helper)
  foreach($a in @($mode,'--service-sid',$match.Value,'--program-data-root',$pd)){$psi.ArgumentList.Add($a)}
  $psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
  $process=[Diagnostics.Process]::Start($psi)
  try{
   $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$process.WaitForExit()
   if($process.ExitCode -ne 0 -or $stdout.GetAwaiter().GetResult() -ne 'OK'){
    throw "Administrator Vault smoke failed at attempt $attempt for $mode with $($stderr.GetAwaiter().GetResult())."
   }
  }finally{$process.Dispose()}
 }
 Write-Host 'Elevated administrator Vault provision, verify, and retry passed.'
}finally{
 if($rootCreated -and (Test-Path -LiteralPath $smokeRoot -PathType Container)){
  $item=Get-Item -LiteralPath $smokeRoot -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Refusing to clean a reparse-point smoke root.'}
  Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction Stop
 }
}
