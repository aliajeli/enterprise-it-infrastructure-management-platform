$ErrorActionPreference="Stop"
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
$installRoot=Join-Path $pf "EnterpriseIT\0.1.113"
$nodePath=(Get-Command node.exe -ErrorAction Stop).Source
$runtimeSource=Split-Path $nodePath -Parent
$nodeVersion=(& $nodePath --version 2>&1|Out-String).Trim()
if($nodeVersion -notmatch '^v26\.'){throw "Windows integration test requires Node.js 26; found $nodeVersion"}
$previousDatabaseUrl=$env:DATABASE_URL
try{
 New-Item -ItemType Directory -Path (Join-Path $installRoot "runtime") -Force|Out-Null
 Get-ChildItem -LiteralPath $runtimeSource -Force|Copy-Item -Destination (Join-Path $installRoot "runtime") -Recurse -Force
 & (Join-Path $PSScriptRoot "stage-node-application-runtime.ps1") -SourceRoot $repoRoot -InstallRoot $installRoot -Confirm:$false|Out-Null
 foreach($file in @("apps\api\dist\server.js","apps\worker\dist\main.js","packages\database\dist\index.js","packages\database\prisma\schema.prisma","node_modules\fastify\package.json","node_modules\@node-rs\argon2\package.json")){if(-not(Test-Path -LiteralPath (Join-Path $installRoot $file) -PathType Leaf)){throw "Staged runtime file is missing: $file"}}
 $env:DATABASE_URL="postgresql://runtime-check:runtime-check@127.0.0.1:5432/runtime_check"
 Push-Location $installRoot
 try{& (Join-Path $installRoot "runtime\node.exe") "--input-type=module" "-e" "await import('@platform/database'); await import('fastify'); await import('@node-rs/argon2'); console.log('Production application runtime smoke passed.');";if($LASTEXITCODE -ne 0){throw "Staged runtime module resolution failed."}}finally{Pop-Location}
 Write-Host "API/Worker production runtime staging integration test passed."
}finally{$env:DATABASE_URL=$previousDatabaseUrl;if(Test-Path -LiteralPath $installRoot){Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue}}