$ErrorActionPreference="Stop"
$scriptPath=Join-Path $PSScriptRoot "new-offline-payload-package.ps1"
$manifestScript=Join-Path $PSScriptRoot "new-offline-payload-manifest.ps1"
$root=Join-Path ([IO.Path]::GetTempPath()) ("enterpriseit-package-test-"+[guid]::NewGuid().ToString("N"))
$out=Join-Path $root "out";$source=Join-Path $root "source";$archive=Join-Path $out "enterpriseit-0.1.1.zip"
New-Item -ItemType Directory -Path $out,$source -Force|Out-Null
try{
 $package=[ordered]@{name="enterprise-it-infrastructure-management-platform";version="0.1.1";private=$true}
 $package|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $source "package.json") -Encoding utf8
 $required=@(
  "runtime\node.exe","runtime\npm.cmd","EnterpriseIT.ApiServiceHost.exe","EnterpriseIT.WebServiceHost.exe","EnterpriseIT.WorkerServiceHost.exe","EnterpriseIT.EdgeServiceHost.exe",
  "apps\api\dist\server.js","apps\worker\dist\main.js","packages\database\dist\index.js","packages\database\prisma\schema.prisma","packages\database\prisma\migrations",
  "node_modules\@platform\api\package.json","node_modules\@platform\worker\package.json","node_modules\@platform\database\package.json","node_modules\fastify\package.json","node_modules\@node-rs\argon2\package.json",
  "apps\web\.next\standalone\server.js","apps\web\.next\standalone\node_modules\next\package.json",
  "postgresql\pgsql\bin\postgres.exe","postgresql\pgsql\bin\pg_ctl.exe","postgresql\pgsql\bin\initdb.exe","postgresql\pgsql\share\postgresql.conf.sample"
 )
 foreach($relative in $required){
  $path=Join-Path $source $relative
  if($relative.EndsWith("\migrations")){New-Item -ItemType Directory -Path $path -Force|Out-Null}
  else{New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force|Out-Null;[IO.File]::WriteAllText($path,"fixture")}
 }
 . $scriptPath -SourceRoot $source -OutputArchive $archive
 $plan=Get-OfflinePayloadPackagePlan -SourceRoot $source -OutputArchive $archive
 if($plan.ApplicationVersion -ne "0.1.1" -or $plan.RequiredFiles.Count -ne $required.Count){throw "Unexpected offline package plan."}
 $dry=& $scriptPath -SourceRoot $source -OutputArchive $archive -WhatIf|ConvertFrom-Json
 if(-not $dry.dryRun -or (Test-Path -LiteralPath $archive)){throw "WhatIf created an archive or failed to report dry-run."}
 & $scriptPath -SourceRoot $source -OutputArchive $archive -Confirm:$false|Out-Null
 if(-not(Test-Path -LiteralPath $archive) -or -not(Test-Path -LiteralPath ($archive+".sha256"))){throw "Offline archive or checksum was not created."}
 $expected=(Get-Content -LiteralPath ($archive+".sha256") -Raw).Trim().Split(" ")[0]
 $actual=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
 if($expected -ne $actual){throw "Archive SHA-256 sidecar does not match the archive."}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $extract=Join-Path $root "extract"
 [IO.Compression.ZipFile]::ExtractToDirectory($archive,$extract)
 . $manifestScript -PayloadRoot $extract
 $verified=Test-OfflinePayloadManifest -PayloadRoot $extract -ExpectedApplicationVersion "0.1.1"
 $expectedPayloadFiles=@($required|Where-Object{$_ -ne "packages\database\prisma\migrations"}).Count+1
 if(-not $verified.valid -or $verified.fileCount -ne $expectedPayloadFiles){throw "Packaged payload manifest file count did not match the staged fixture."}
 $rejected=$false;try{Get-OfflinePayloadPackagePlan -SourceRoot $source -OutputArchive $archive|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Existing archive overwrite was not rejected."}
 $incomplete=Join-Path $root "incomplete";New-Item -ItemType Directory -Path $incomplete -Force|Out-Null
 Copy-Item -LiteralPath (Join-Path $source "package.json") -Destination $incomplete
 $rejected=$false;try{Get-OfflinePayloadPackagePlan -SourceRoot $incomplete -OutputArchive (Join-Path $out "bad.zip")|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Incomplete staged payload was accepted."}
 $outside=Join-Path $root "outside";$junction=Join-Path $source "external-link"
 New-Item -ItemType Directory -Path $outside -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $outside "outside.txt"),"must not be packaged")
 New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop|Out-Null
 $rejected=$false;try{Get-OfflinePayloadPackagePlan -SourceRoot $source -OutputArchive (Join-Path $out "junction.zip")|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Source tree containing a junction/reparse point was accepted."}
 Remove-Item -LiteralPath $junction -Force -ErrorAction Stop
 Write-Host "Offline payload package tests passed."
}finally{if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}}
