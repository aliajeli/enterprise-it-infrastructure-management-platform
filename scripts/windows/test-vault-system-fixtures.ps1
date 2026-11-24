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
$smokePath=Join-Path $env:RUNNER_TEMP 'enterpriseit-vault-admin-smoke'
function Escape-SingleQuoted([string]$s){return $s.Replace("'","''")}
$worker=@'
$ErrorActionPreference='Stop'
$result=@{success=$false;message='Fixture process did not complete.'}
try {
 & '__TEST_PATH__'
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
$worker=$worker.Replace('__TEST_PATH__',(Escape-SingleQuoted $testPath)).Replace('__SMOKE_PATH__',(Escape-SingleQuoted $smokePath)).Replace('__RESULT_PATH__',(Escape-SingleQuoted $resultPath))
[IO.File]::WriteAllText($scriptPath,$worker,[Text.UTF8Encoding]::new($false))
$pwsh=Join-Path $PSHOME 'pwsh.exe'
$command='"'+$pwsh+'" -NoLogo -NoProfile -NonInteractive -File "'+$scriptPath+'"'
try{
 & schtasks.exe /Create /TN $taskName /SC ONCE /ST 23:59 /RU SYSTEM /TR $command /F | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not create isolated SYSTEM fixture task.'}
 & schtasks.exe /Run /TN $taskName | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not start isolated SYSTEM fixture task.'}
 $deadline=[DateTime]::UtcNow.AddSeconds(120)
 while(-not(Test-Path -LiteralPath $resultPath -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 1}
 if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'SYSTEM fixture task timed out.'}
 $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
 if(-not $result.success){throw "SYSTEM Vault fixture test failed: $($result.message)"}
 Write-Host 'Independent SYSTEM ACL and adversarial Vault fixtures passed.'
}finally{
 & schtasks.exe /End /TN $taskName 2>$null | Out-Null
 & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
 foreach($path in @($scriptPath,$resultPath)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
}
