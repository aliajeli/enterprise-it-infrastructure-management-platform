# Isolated Windows CI test. No migration is executed and no database is used.
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $env:RUNNER_TEMP){throw 'This test requires a disposable Windows CI runner.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
$digits=([guid]::NewGuid().ToString('N') -replace '[^0-9]','')
if($digits.Length -lt 8){throw 'Could not allocate test version.'}
$root=Join-Path $pf ('EnterpriseIT\0.0.'+$digits)
$created=$false
if(Test-Path -LiteralPath $root){throw 'Refusing to adopt an existing version directory.'}

try{
 New-Item -ItemType Directory -Path $root -ErrorAction Stop|Out-Null;$created=$true
 $runtime=Split-Path (Get-Command node.exe -ErrorAction Stop).Source -Parent
 & (Join-Path $PSScriptRoot 'stage-node-runtime.ps1') -NodeRuntimeDirectory $runtime -InstallRoot $root -Confirm:$false|Out-Null
 $script=Join-Path $PSScriptRoot 'stage-migration-tool.ps1'
 $dry=& $script -SourceRoot $repo -InstallRoot $root -WhatIf|ConvertFrom-Json
 if(-not $dry.dryRun -or $dry.databaseMutated -or (Test-Path -LiteralPath (Join-Path $root 'migration-tool'))){throw 'Migration tool WhatIf must be read-only.'}
 & $script -SourceRoot $repo -InstallRoot $root -Confirm:$false|Out-Null
 New-Item -ItemType Directory -Path (Join-Path $root 'packages\database') -ErrorAction Stop|Out-Null
 Copy-Item -LiteralPath (Join-Path $repo 'packages\database\prisma') -Destination (Join-Path $root 'packages\database\prisma') -Recurse
 & (Join-Path $PSScriptRoot 'test-migration-tool-offline.ps1') -Root $root|Out-Null
 $blocked=$false
 try{& $script -SourceRoot $repo -InstallRoot $root -Confirm:$false|Out-Null}catch{$blocked=$true}
 if(-not $blocked){throw 'Migration tooling overwrite must be rejected.'}
 Write-Host 'Isolated pinned Prisma tooling and local schema validation passed; database migrations remain disabled.'
}finally{
 if($created -and (Test-Path -LiteralPath $root)){
  $item=Get-Item -LiteralPath $root -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Refusing to remove a replaced test root.'}
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
 }
}
