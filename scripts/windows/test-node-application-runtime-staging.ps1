$ErrorActionPreference="Stop"
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$package=Get-Content -LiteralPath (Join-Path $repoRoot "package.json") -Raw|ConvertFrom-Json
$version=[string]$package.version
if($version -notmatch '^\d+\.\d+\.\d+$'){throw "Root package version is invalid: $version"}
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
$installRoot=Join-Path $pf ("EnterpriseIT\"+$version)
$nodePath=(Get-Command node.exe -ErrorAction Stop).Source
$runtimeSource=Split-Path $nodePath -Parent
$nodeVersion=(& $nodePath --version 2>&1|Out-String).Trim()
if($nodeVersion -notmatch '^v26\.'){throw "Windows integration test requires Node.js 26; found $nodeVersion"}
$previousDatabaseUrl=$env:DATABASE_URL
try{
 New-Item -ItemType Directory -Path (Join-Path $installRoot "runtime") -Force|Out-Null
 Get-ChildItem -LiteralPath $runtimeSource -Force|Copy-Item -Destination (Join-Path $installRoot "runtime") -Recurse -Force
 & (Join-Path $PSScriptRoot "stage-node-application-runtime.ps1") -SourceRoot $repoRoot -InstallRoot $installRoot -Confirm:$false|Out-Null
 foreach($file in @("apps\api\dist\server.js","apps\worker\dist\main.js","packages\database\dist\index.js","packages\database\prisma\schema.prisma","node_modules\fastify\package.json","node_modules\@node-rs\argon2\package.json","node_modules\@platform\api\package.json","node_modules\@platform\worker\package.json","node_modules\@platform\database\package.json")){
  if(-not(Test-Path -LiteralPath (Join-Path $installRoot $file) -PathType Leaf)){throw "Staged runtime file is missing: $file"}
 }
 $env:DATABASE_URL="postgresql://runtime-check:runtime-check@127.0.0.1:5432/runtime_check"
 foreach($workingDirectory in @((Join-Path $installRoot "apps\api"),(Join-Path $installRoot "apps\worker"))){
  Push-Location $workingDirectory
  try{
   & (Join-Path $installRoot "runtime\node.exe") "--input-type=module" "-e" "await import('@platform/database'); await import('fastify'); await import('@node-rs/argon2'); console.log('Production application runtime smoke passed.');"
   if($LASTEXITCODE -ne 0){throw "Staged runtime module resolution failed from $workingDirectory."}
  }finally{Pop-Location}
 }
 Write-Host "API/Worker production runtime staging integration test passed."
}finally{$env:DATABASE_URL=$previousDatabaseUrl;if(Test-Path -LiteralPath $installRoot){Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue}}
