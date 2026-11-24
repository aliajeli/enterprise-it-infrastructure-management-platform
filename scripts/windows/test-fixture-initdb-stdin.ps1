# Synthetic child only: never used for a real database.
$ErrorActionPreference='Stop'
$expected='synthetic-initdb-stdin-password-42'
if(([Environment]::GetCommandLineArgs() -join ' ').Contains($expected)){exit 11}
if($null -ne [Environment]::GetEnvironmentVariable('PG_RESTRICT_EXEC')){exit 12}
if([Environment]::GetEnvironmentVariable('OSTYPE') -cne 'msys'){exit 16}
if($args -contains '--fixture-timeout'){Start-Sleep -Seconds 15;exit 13}
if($args -notcontains '--pwprompt' -or @($args|Where-Object{$_ -like '--pwfile=*'}).Count -ne 0){exit 14}
$first=[Console]::In.ReadLine();$second=[Console]::In.ReadLine()
if($first -cne $expected -or $second -cne $expected){exit 15}
# Both streams deliberately contain the synthetic value; the parent must suppress them.
[Console]::Out.Write($first);[Console]::Error.Write($second)
exit 0
