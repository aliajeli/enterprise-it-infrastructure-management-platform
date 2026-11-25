$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'experimental-initdb-pipe.ps1')
$fixture=Join-Path $PSScriptRoot 'test-fixture-initdb-pipe.ps1'
$pwsh=[IO.Path]::GetFullPath((Join-Path $PSHOME 'pwsh.exe'))
$secret=ConvertTo-SecureString 'synthetic-initdb-secret-42' -AsPlainText -Force
$fakeData=Join-Path $env:TEMP ('enterpriseit-pipe-no-data-'+[guid]::NewGuid().ToString('N'))
$result=Invoke-ExperimentalInitDbPipe -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture) -DataPath $fakeData -Password $secret -TimeoutSeconds 20
if($result.status -ne 'ok' -or $result.transport -ne 'current-user-named-pipe' -or $result.plaintextFileCreated -or (Test-Path -LiteralPath $fakeData)){throw 'Synthetic initdb pipe test failed.'}
if(($result|ConvertTo-Json -Compress) -like '*synthetic-initdb-secret-42*'){throw 'Secret appeared in pipe result.'}
# UTF-8 multi-byte characters and surrogate pairs survive the clearable
# character-array conversion without constructing a plaintext result.
$unicodeValue='synthetic-'+[char]0x00f6+'-secret-'+[char]0xd83d+[char]0xde80+'-42'
$unicodeSecret=ConvertTo-SecureString $unicodeValue -AsPlainText -Force
$unicodeResult=Invoke-ExperimentalInitDbPipe -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture,'--fixture-unicode') -DataPath $fakeData -Password $unicodeSecret -TimeoutSeconds 20
if($unicodeResult.status -ne 'ok' -or ($unicodeResult|ConvertTo-Json -Compress).Contains($unicodeValue)){throw 'Unicode synthetic pipe test failed or leaked a marker.'}
$unicodeValue=$null
$blocked=$false
try{Invoke-ExperimentalInitDbPipe -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture,'--fixture-timeout') -DataPath $fakeData -Password $secret -TimeoutSeconds 2|Out-Null}catch{
 if($_.Exception.Message -like '*synthetic-initdb-secret-42*'){throw 'Secret appeared in failure message.'}
 $blocked=$true
}
if(-not $blocked -or (Test-Path -LiteralPath $fakeData)){throw 'Nonconnecting child must be terminated without data mutation.'}
$blocked=$false
try{Invoke-ExperimentalInitDbPipe -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture,'--fixture-wrong-client') -DataPath $fakeData -Password $secret -TimeoutSeconds 10|Out-Null}catch{
 if($_.Exception.Message -notmatch '^Experimental initdb pipe operation failed at verify-client-pid-mismatch-(direct-same-image|other|unavailable)\.$'){throw 'Wrong-client fixture did not reach the fixed-only PID mismatch guard.'}
 $blocked=$true
}
if(-not $blocked){throw 'A different same-user process must not receive the pipe credential.'}
$bad=ConvertTo-SecureString "invalid-password-with`nnewline" -AsPlainText -Force
# An invalid marker on an unauthorized connection must reach the PID guard,
# not credential preparation; this is ordering evidence, not process isolation.
$blocked=$false
try{Invoke-ExperimentalInitDbPipe -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture,'--fixture-wrong-client') -DataPath $fakeData -Password $bad -TimeoutSeconds 10|Out-Null}catch{
 if($_.Exception.Message -notmatch '^Experimental initdb pipe operation failed at verify-client-pid-mismatch-(direct-same-image|other|unavailable)\.$'){throw 'Wrong-client path unexpectedly reached credential preparation.'}
 $blocked=$true
}
if(-not $blocked){throw 'Wrong client unexpectedly accepted an invalid synthetic secret.'}
$blocked=$false
try{Invoke-ExperimentalInitDbPipe -Executable $pwsh -TestPrefixArguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$fixture) -DataPath $fakeData -Password $bad -TimeoutSeconds 10|Out-Null}catch{
 $blocked=$_.Exception.Message -eq 'Experimental initdb pipe operation failed at credential-preparation.'
}
if(-not $blocked){throw 'Newline-bearing secret must be rejected during credential preparation.'}
Write-Host 'Experimental initdb pipe synthetic tests passed; real initdb transport remains disabled.'
