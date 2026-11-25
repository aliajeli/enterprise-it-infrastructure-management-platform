# CI-only independent ACL/adversarial fixture runner. Production provisioning must
# also pass the separate elevated administrator smoke test; this is not a runtime
# fallback identity. LocalSystem is an explicitly authorized Vault ACL principal.
$ErrorActionPreference='Stop'
if(-not $env:RUNNER_TEMP){throw 'CI runner temporary directory is required.'}
$id=[guid]::NewGuid().ToString('N')
$taskName='EnterpriseITVaultFixture-'+$id
$scriptPath=Join-Path $env:RUNNER_TEMP ('vault-fixture-'+$id+'.ps1')
$resultPath=Join-Path $env:RUNNER_TEMP ('vault-fixture-'+$id+'.json')
$testPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'test-credential-vault-provisioning.ps1'))
$smokePath=''
if($env:ENTERPRISEIT_VAULT_ADMIN_SMOKE_ROOT){
 $smokePath=[IO.Path]::GetFullPath($env:ENTERPRISEIT_VAULT_ADMIN_SMOKE_ROOT)
 $volumeRoot=[IO.Path]::GetPathRoot($env:SystemRoot)
 if([IO.Path]::GetDirectoryName($smokePath) -ne $volumeRoot -or [IO.Path]::GetFileName($smokePath) -notmatch '^EnterpriseIT-Vault-Admin-Smoke-[0-9a-f]{32}
# in normal bin/obj, the payload, or any release artifact.
$buildRoot=Join-Path $env:RUNNER_TEMP ('vault-fault-build-'+$id)
$outDir=Join-Path $buildRoot 'out'
$sourceDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\apps\api\windows\keyring-storage-helper'))
$fixtureSource=Join-Path $buildRoot 'source'
$project=Join-Path $fixtureSource 'CredentialVault.KeyringStorageHelper.csproj'
$faultHelper=Join-Path $outDir 'CredentialVault.KeyringStorageHelper.exe'
New-Item -ItemType Directory -Path $fixtureSource -ErrorAction Stop|Out-Null
# Copy sources only. Building the original project with an alternate obj path
# makes the original obj tree eligible for wildcard compilation, duplicating
# assembly attributes; copying also prevents test build contamination.
Copy-Item -LiteralPath (Join-Path $sourceDir 'CredentialVault.KeyringStorageHelper.csproj') -Destination $project
foreach($source in Get-ChildItem -LiteralPath $sourceDir -Filter '*.cs' -File){Copy-Item -LiteralPath $source.FullName -Destination $fixtureSource}
& dotnet build $project --configuration Release --output $outDir '-p:DefineConstants=VAULT_TEST_FAULTS'
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $faultHelper -PathType Leaf)){
 Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
 throw 'Could not build isolated Vault fault fixture executable.'
}
function Escape-SingleQuoted([string]$s){return $s.Replace("'","''")}
$worker=@'
$ErrorActionPreference='Stop'
$result=@{success=$false;message='Fixture process did not complete.'}
try {
 & '__TEST_PATH__' -FaultHelperPath '__FAULT_HELPER__'
 $result.success=$true
 $result.message=''
} catch {
 $result.message=$_.Exception.Message
} finally {
 # The admin smoke hands off only its GUID-scoped volume-root fixture.
 if('__SMOKE_PATH__' -ne '' -and (Test-Path -LiteralPath '__SMOKE_PATH__')) {
  try {
   $item=Get-Item -LiteralPath '__SMOKE_PATH__' -Force
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Refusing a reparse-point admin fixture root.'}
   Remove-Item -LiteralPath '__SMOKE_PATH__' -Recurse -Force -ErrorAction Stop
  } catch { $result.success=$false; $result.message='Admin smoke fixture cleanup failed.' }
 }
 $result | ConvertTo-Json -Compress | Set-Content -LiteralPath '__RESULT_PATH__' -Encoding utf8
}
'@
$worker=$worker.Replace('__TEST_PATH__',(Escape-SingleQuoted $testPath)).Replace('__FAULT_HELPER__',(Escape-SingleQuoted $faultHelper)).Replace('__SMOKE_PATH__',(Escape-SingleQuoted $smokePath)).Replace('__RESULT_PATH__',(Escape-SingleQuoted $resultPath))
[IO.File]::WriteAllText($scriptPath,$worker,[Text.UTF8Encoding]::new($false))
$pwsh=Join-Path $PSHOME 'pwsh.exe'
$command='"'+$pwsh+'" -NoLogo -NoProfile -NonInteractive -File "'+$scriptPath+'"'
try{
 & schtasks.exe /Create /TN $taskName /SC ONCE /ST 23:59 /RU SYSTEM /TR $command /F | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not create isolated SYSTEM fixture task.'}
 & schtasks.exe /Run /TN $taskName | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not start isolated SYSTEM fixture task.'}
 $deadline=[DateTime]::UtcNow.AddSeconds(240)
 while(-not(Test-Path -LiteralPath $resultPath -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 1}
 if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'SYSTEM fixture task timed out.'}
 $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
 if(-not $result.success){throw "SYSTEM Vault fixture test failed: $($result.message)"}
 Write-Host 'Independent SYSTEM ACL and adversarial Vault fixtures passed.'
}finally{
 & schtasks.exe /End /TN $taskName 2>$null | Out-Null
 & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
 foreach($path in @($scriptPath,$resultPath)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
 if(Test-Path -LiteralPath $buildRoot){Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue}
 Remove-Item Env:\ENTERPRISEIT_VAULT_ADMIN_SMOKE_ROOT -ErrorAction SilentlyContinue
}
){
  throw 'Refusing an out-of-scope admin Vault fixture cleanup path.'
 }
}
# Build a separate test-only executable; do not place its instrumented output
# in normal bin/obj, the payload, or any release artifact.
$buildRoot=Join-Path $env:RUNNER_TEMP ('vault-fault-build-'+$id)
$outDir=Join-Path $buildRoot 'out'
$sourceDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\apps\api\windows\keyring-storage-helper'))
$fixtureSource=Join-Path $buildRoot 'source'
$project=Join-Path $fixtureSource 'CredentialVault.KeyringStorageHelper.csproj'
$faultHelper=Join-Path $outDir 'CredentialVault.KeyringStorageHelper.exe'
New-Item -ItemType Directory -Path $fixtureSource -ErrorAction Stop|Out-Null
# Copy sources only. Building the original project with an alternate obj path
# makes the original obj tree eligible for wildcard compilation, duplicating
# assembly attributes; copying also prevents test build contamination.
Copy-Item -LiteralPath (Join-Path $sourceDir 'CredentialVault.KeyringStorageHelper.csproj') -Destination $project
foreach($source in Get-ChildItem -LiteralPath $sourceDir -Filter '*.cs' -File){Copy-Item -LiteralPath $source.FullName -Destination $fixtureSource}
& dotnet build $project --configuration Release --output $outDir '-p:DefineConstants=VAULT_TEST_FAULTS'
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $faultHelper -PathType Leaf)){
 Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
 throw 'Could not build isolated Vault fault fixture executable.'
}
function Escape-SingleQuoted([string]$s){return $s.Replace("'","''")}
$worker=@'
$ErrorActionPreference='Stop'
$result=@{success=$false;message='Fixture process did not complete.'}
try {
 & '__TEST_PATH__' -FaultHelperPath '__FAULT_HELPER__'
 $result.success=$true
 $result.message=''
} catch {
 $result.message=$_.Exception.Message
} finally {
 # This directory is created only by the immediately preceding admin CI smoke.
 if(Test-Path -LiteralPath '__SMOKE_PATH__') {
  try { Remove-Item -LiteralPath '__SMOKE_PATH__' -Recurse -Force -ErrorAction Stop }
  catch { $result.success=$false; $result.message='Admin smoke fixture cleanup failed.' }
 }
 $result | ConvertTo-Json -Compress | Set-Content -LiteralPath '__RESULT_PATH__' -Encoding utf8
}
'@
$worker=$worker.Replace('__TEST_PATH__',(Escape-SingleQuoted $testPath)).Replace('__FAULT_HELPER__',(Escape-SingleQuoted $faultHelper)).Replace('__SMOKE_PATH__',(Escape-SingleQuoted $smokePath)).Replace('__RESULT_PATH__',(Escape-SingleQuoted $resultPath))
[IO.File]::WriteAllText($scriptPath,$worker,[Text.UTF8Encoding]::new($false))
$pwsh=Join-Path $PSHOME 'pwsh.exe'
$command='"'+$pwsh+'" -NoLogo -NoProfile -NonInteractive -File "'+$scriptPath+'"'
try{
 & schtasks.exe /Create /TN $taskName /SC ONCE /ST 23:59 /RU SYSTEM /TR $command /F | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not create isolated SYSTEM fixture task.'}
 & schtasks.exe /Run /TN $taskName | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not start isolated SYSTEM fixture task.'}
 $deadline=[DateTime]::UtcNow.AddSeconds(240)
 while(-not(Test-Path -LiteralPath $resultPath -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 1}
 if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'SYSTEM fixture task timed out.'}
 $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
 if(-not $result.success){throw "SYSTEM Vault fixture test failed: $($result.message)"}
 Write-Host 'Independent SYSTEM ACL and adversarial Vault fixtures passed.'
}finally{
 & schtasks.exe /End /TN $taskName 2>$null | Out-Null
 & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
 foreach($path in @($scriptPath,$resultPath)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
 if(Test-Path -LiteralPath $buildRoot){Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
){
  throw 'Refusing an out-of-scope admin Vault fixture cleanup path.'
 }
}
# Build a separate test-only executable; do not place its instrumented output
# in normal bin/obj, the payload, or any release artifact.
$buildRoot=Join-Path $env:RUNNER_TEMP ('vault-fault-build-'+$id)
$outDir=Join-Path $buildRoot 'out'
$sourceDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\apps\api\windows\keyring-storage-helper'))
$fixtureSource=Join-Path $buildRoot 'source'
$project=Join-Path $fixtureSource 'CredentialVault.KeyringStorageHelper.csproj'
$faultHelper=Join-Path $outDir 'CredentialVault.KeyringStorageHelper.exe'
New-Item -ItemType Directory -Path $fixtureSource -ErrorAction Stop|Out-Null
# Copy sources only. Building the original project with an alternate obj path
# makes the original obj tree eligible for wildcard compilation, duplicating
# assembly attributes; copying also prevents test build contamination.
Copy-Item -LiteralPath (Join-Path $sourceDir 'CredentialVault.KeyringStorageHelper.csproj') -Destination $project
foreach($source in Get-ChildItem -LiteralPath $sourceDir -Filter '*.cs' -File){Copy-Item -LiteralPath $source.FullName -Destination $fixtureSource}
& dotnet build $project --configuration Release --output $outDir '-p:DefineConstants=VAULT_TEST_FAULTS'
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $faultHelper -PathType Leaf)){
 Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
 throw 'Could not build isolated Vault fault fixture executable.'
}
function Escape-SingleQuoted([string]$s){return $s.Replace("'","''")}
$worker=@'
$ErrorActionPreference='Stop'
$result=@{success=$false;message='Fixture process did not complete.'}
try {
 & '__TEST_PATH__' -FaultHelperPath '__FAULT_HELPER__'
 $result.success=$true
 $result.message=''
} catch {
 $result.message=$_.Exception.Message
} finally {
 # The admin smoke hands off only its GUID-scoped volume-root fixture.
 if('__SMOKE_PATH__' -ne '' -and (Test-Path -LiteralPath '__SMOKE_PATH__')) {
  try {
   $item=Get-Item -LiteralPath '__SMOKE_PATH__' -Force
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Refusing a reparse-point admin fixture root.'}
   Remove-Item -LiteralPath '__SMOKE_PATH__' -Recurse -Force -ErrorAction Stop
  } catch { $result.success=$false; $result.message='Admin smoke fixture cleanup failed.' }
 }
 $result | ConvertTo-Json -Compress | Set-Content -LiteralPath '__RESULT_PATH__' -Encoding utf8
}
'@
$worker=$worker.Replace('__TEST_PATH__',(Escape-SingleQuoted $testPath)).Replace('__FAULT_HELPER__',(Escape-SingleQuoted $faultHelper)).Replace('__SMOKE_PATH__',(Escape-SingleQuoted $smokePath)).Replace('__RESULT_PATH__',(Escape-SingleQuoted $resultPath))
[IO.File]::WriteAllText($scriptPath,$worker,[Text.UTF8Encoding]::new($false))
$pwsh=Join-Path $PSHOME 'pwsh.exe'
$command='"'+$pwsh+'" -NoLogo -NoProfile -NonInteractive -File "'+$scriptPath+'"'
try{
 & schtasks.exe /Create /TN $taskName /SC ONCE /ST 23:59 /RU SYSTEM /TR $command /F | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not create isolated SYSTEM fixture task.'}
 & schtasks.exe /Run /TN $taskName | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not start isolated SYSTEM fixture task.'}
 $deadline=[DateTime]::UtcNow.AddSeconds(240)
 while(-not(Test-Path -LiteralPath $resultPath -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 1}
 if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'SYSTEM fixture task timed out.'}
 $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
 if(-not $result.success){throw "SYSTEM Vault fixture test failed: $($result.message)"}
 Write-Host 'Independent SYSTEM ACL and adversarial Vault fixtures passed.'
}finally{
 & schtasks.exe /End /TN $taskName 2>$null | Out-Null
 & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
 foreach($path in @($scriptPath,$resultPath)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
 if(Test-Path -LiteralPath $buildRoot){Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue}
 Remove-Item Env:\ENTERPRISEIT_VAULT_ADMIN_SMOKE_ROOT -ErrorAction SilentlyContinue
}
){
  throw 'Refusing an out-of-scope admin Vault fixture cleanup path.'
 }
}
# Build a separate test-only executable; do not place its instrumented output
# in normal bin/obj, the payload, or any release artifact.
$buildRoot=Join-Path $env:RUNNER_TEMP ('vault-fault-build-'+$id)
$outDir=Join-Path $buildRoot 'out'
$sourceDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\apps\api\windows\keyring-storage-helper'))
$fixtureSource=Join-Path $buildRoot 'source'
$project=Join-Path $fixtureSource 'CredentialVault.KeyringStorageHelper.csproj'
$faultHelper=Join-Path $outDir 'CredentialVault.KeyringStorageHelper.exe'
New-Item -ItemType Directory -Path $fixtureSource -ErrorAction Stop|Out-Null
# Copy sources only. Building the original project with an alternate obj path
# makes the original obj tree eligible for wildcard compilation, duplicating
# assembly attributes; copying also prevents test build contamination.
Copy-Item -LiteralPath (Join-Path $sourceDir 'CredentialVault.KeyringStorageHelper.csproj') -Destination $project
foreach($source in Get-ChildItem -LiteralPath $sourceDir -Filter '*.cs' -File){Copy-Item -LiteralPath $source.FullName -Destination $fixtureSource}
& dotnet build $project --configuration Release --output $outDir '-p:DefineConstants=VAULT_TEST_FAULTS'
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $faultHelper -PathType Leaf)){
 Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
 throw 'Could not build isolated Vault fault fixture executable.'
}
function Escape-SingleQuoted([string]$s){return $s.Replace("'","''")}
$worker=@'
$ErrorActionPreference='Stop'
$result=@{success=$false;message='Fixture process did not complete.'}
try {
 & '__TEST_PATH__' -FaultHelperPath '__FAULT_HELPER__'
 $result.success=$true
 $result.message=''
} catch {
 $result.message=$_.Exception.Message
} finally {
 # This directory is created only by the immediately preceding admin CI smoke.
 if(Test-Path -LiteralPath '__SMOKE_PATH__') {
  try { Remove-Item -LiteralPath '__SMOKE_PATH__' -Recurse -Force -ErrorAction Stop }
  catch { $result.success=$false; $result.message='Admin smoke fixture cleanup failed.' }
 }
 $result | ConvertTo-Json -Compress | Set-Content -LiteralPath '__RESULT_PATH__' -Encoding utf8
}
'@
$worker=$worker.Replace('__TEST_PATH__',(Escape-SingleQuoted $testPath)).Replace('__FAULT_HELPER__',(Escape-SingleQuoted $faultHelper)).Replace('__SMOKE_PATH__',(Escape-SingleQuoted $smokePath)).Replace('__RESULT_PATH__',(Escape-SingleQuoted $resultPath))
[IO.File]::WriteAllText($scriptPath,$worker,[Text.UTF8Encoding]::new($false))
$pwsh=Join-Path $PSHOME 'pwsh.exe'
$command='"'+$pwsh+'" -NoLogo -NoProfile -NonInteractive -File "'+$scriptPath+'"'
try{
 & schtasks.exe /Create /TN $taskName /SC ONCE /ST 23:59 /RU SYSTEM /TR $command /F | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not create isolated SYSTEM fixture task.'}
 & schtasks.exe /Run /TN $taskName | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not start isolated SYSTEM fixture task.'}
 $deadline=[DateTime]::UtcNow.AddSeconds(240)
 while(-not(Test-Path -LiteralPath $resultPath -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 1}
 if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'SYSTEM fixture task timed out.'}
 $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
 if(-not $result.success){throw "SYSTEM Vault fixture test failed: $($result.message)"}
 Write-Host 'Independent SYSTEM ACL and adversarial Vault fixtures passed.'
}finally{
 & schtasks.exe /End /TN $taskName 2>$null | Out-Null
 & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
 foreach($path in @($scriptPath,$resultPath)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
 if(Test-Path -LiteralPath $buildRoot){Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
