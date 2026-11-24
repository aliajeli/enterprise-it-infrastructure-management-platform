# Builds six actual self-contained Windows executables in an isolated CI path.
# This does not install or start services, and does not constitute an installer.
$ErrorActionPreference='Stop'
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
$digits=([guid]::NewGuid().ToString('N') -replace '[^0-9]','')
if($digits.Length -lt 8){throw 'Could not allocate an isolated version directory.'}
$root=Join-Path $pf ('EnterpriseIT\0.0.'+$digits)
if(Test-Path -LiteralPath $root){throw 'Refusing to use an existing version directory.'}
$created=$false
try{
 New-Item -ItemType Directory -Path $root -ErrorAction Stop|Out-Null
 $created=$true
 $script=Join-Path $PSScriptRoot 'stage-windows-service-hosts.ps1'
 & $script -InstallRoot $root -Confirm:$false | Out-Null
 $names=@('EnterpriseIT.ApiServiceHost.exe','EnterpriseIT.WebServiceHost.exe','EnterpriseIT.WorkerServiceHost.exe','EnterpriseIT.EdgeServiceHost.exe','CredentialVault.KeyringStorageHelper.exe','CredentialVault.DpapiHelper.exe')
 foreach($name in $names){
  $path=Join-Path $root $name
  if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -lt 1MB){throw "Missing or incomplete self-contained fixture: $name"}
 }
 $first=Join-Path $root $names[0]
 $before=(Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash
 $rejected=$false
 try{& $script -InstallRoot $root -Confirm:$false|Out-Null}catch{$rejected=$true}
 if(-not $rejected -or $before -ne (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash){throw 'Published immutable executables must not be overwritten.'}
 Write-Host 'Six self-contained service-host/helper publications passed; no services were installed.'
}finally{
 if($created -and (Test-Path -LiteralPath $root)){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
