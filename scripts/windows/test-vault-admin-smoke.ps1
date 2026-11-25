# The provisioner must work from the elevated runner account, not just LocalSystem.
# Place the disposable fixture directly below the OS ProgramData directory so
# the test exercises a production-like trusted ancestor chain, not runner TEMP ACLs.
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($identity.User.Value -eq 'S-1-5-18'){throw 'Administrator smoke must not run as LocalSystem.'}
$smokeRoot=Join-Path $env:ProgramData ('EnterpriseIT-Vault-Admin-Smoke-' + [guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $smokeRoot){throw 'Refusing to adopt an existing smoke-test directory.'}
$pd=Join-Path $smokeRoot 'ProgramData'
[IO.Directory]::CreateDirectory($pd)|Out-Null
$acl=[Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true,$false)
foreach($sid in @('S-1-5-18','S-1-5-32-544')){
 $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
 $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $pd -AclObject $acl
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
 $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$process.WaitForExit()
 if($process.ExitCode -ne 0 -or $stdout.GetAwaiter().GetResult() -ne 'OK'){
  throw "Administrator Vault smoke failed at attempt $attempt for $mode with $($stderr.GetAwaiter().GetResult())."
 }
}
Write-Host 'Elevated administrator Vault provision, verify, and retry passed.'
Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction Stop
