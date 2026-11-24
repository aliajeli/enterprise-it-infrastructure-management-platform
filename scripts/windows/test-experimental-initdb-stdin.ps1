Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'experimental-initdb-stdin.ps1')
$fixture=Join-Path $PSScriptRoot 'test-fixture-initdb-stdin.ps1'
$pwsh=[IO.Path]::GetFullPath((Join-Path $PSHOME 'pwsh.exe'))
$secret=ConvertTo-SecureString 'synthetic-initdb-stdin-password-42' -AsPlainText -Force
$fakeData=Join-Path $env:TEMP ('enterpriseit-stdin-no-data-'+[guid]::NewGuid().ToString('N'))
$previous=[Environment]::GetEnvironmentVariable('PG_RESTRICT_EXEC','Process')
try{
 [Environment]::SetEnvironmentVariable('PG_RESTRICT_EXEC','1','Process')
 $results=@(Invoke-ExperimentalInitDbStdin -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture) -DataPath $fakeData -Password $secret -TimeoutSeconds 20)
 if($results.Count -ne 1){throw 'Synthetic stdin transport must return exactly one result object.'}
 $result=$results[0]
 if($result.status -ne 'ok' -or $result.transport -ne 'inherited-anonymous-stdin' -or $result.plaintextFileCreated -or (Test-Path -LiteralPath $fakeData)){throw 'Synthetic stdin test failed.'}
 if(($result|ConvertTo-Json -Compress) -like '*synthetic-initdb-stdin-password-42*'){throw 'Secret appeared in stdin result.'}
 $blocked=$false
 try{Invoke-ExperimentalInitDbStdin -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture,'--fixture-timeout') -DataPath $fakeData -Password $secret -TimeoutSeconds 2|Out-Null}catch{
  if($_.Exception.Message -like '*synthetic-initdb-stdin-password-42*'){throw 'Secret appeared in failure message.'}
  $blocked=$_.Exception.Message -like '*wait-child*'
 }
 if(-not $blocked -or (Test-Path -LiteralPath $fakeData)){throw 'Nonterminating child must time out without data mutation.'}
 $blocked=$false
 try{Invoke-ExperimentalInitDbStdin -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture,'--fixture-restrict-failure') -DataPath $fakeData -Password $secret -TimeoutSeconds 20|Out-Null}catch{$blocked=$_.Exception.Message -like '*restricted-reexec-error*'}
 if(-not $blocked){throw 'Reported restricted re-exec failure must not be treated as success.'}
 $bad=ConvertTo-SecureString "invalid-password-with`nnewline" -AsPlainText -Force
 $blocked=$false
 try{Invoke-ExperimentalInitDbStdin -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture) -DataPath $fakeData -Password $bad -TimeoutSeconds 2|Out-Null}catch{$blocked=$true}
 if(-not $blocked){throw 'Newline-bearing password must be rejected.'}
}finally{[Environment]::SetEnvironmentVariable('PG_RESTRICT_EXEC',$previous,'Process')}
Write-Host 'Experimental stdin synthetic tests passed; production remains disabled.'
