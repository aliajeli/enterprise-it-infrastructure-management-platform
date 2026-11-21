$ErrorActionPreference="Stop"
$scriptPath=Join-Path $PSScriptRoot "new-offline-payload-manifest.ps1"
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ("enterpriseit-manifest-test-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force|Out-Null
try{
 . $scriptPath -PayloadRoot $tempRoot
 $api=Join-Path $tempRoot "apps\api\dist";$worker=Join-Path $tempRoot "apps\worker\dist"
 New-Item -ItemType Directory -Path $api,$worker -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $api "server.js"),"console.log('api');")
 [IO.File]::WriteAllText((Join-Path $worker "main.js"),"console.log('worker');")
 $created=New-OfflinePayloadManifest -PayloadRoot $tempRoot -ApplicationVersion "0.1.109"
 if($created.fileCount -ne 2){throw "Manifest did not inventory both payload files."}
 $verified=Test-OfflinePayloadManifest -PayloadRoot $tempRoot -ExpectedApplicationVersion "0.1.109"
 if(-not $verified.valid -or $verified.fileCount -ne 2){throw "Valid payload failed verification."}
 [IO.File]::AppendAllText((Join-Path $api "server.js"),"//tampered")
 $rejected=$false;try{Test-OfflinePayloadManifest -PayloadRoot $tempRoot|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Modified content was not rejected."}
 [IO.File]::WriteAllText((Join-Path $api "server.js"),"console.log('api');")
 [IO.File]::WriteAllText((Join-Path $tempRoot "unexpected.txt"),"unexpected")
 $rejected=$false;try{Test-OfflinePayloadManifest -PayloadRoot $tempRoot|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Unexpected file was not rejected."}
 Remove-Item -LiteralPath (Join-Path $tempRoot "unexpected.txt") -Force
 $rejected=$false;try{Test-OfflinePayloadManifest -PayloadRoot $tempRoot -ExpectedApplicationVersion "0.1.108"|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Version mismatch was not rejected."}
 $manifestPath=Join-Path $tempRoot "payload.manifest.json";$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
 $manifest.files[0].path="../outside.txt";$manifest|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $manifestPath
 $rejected=$false;try{Test-OfflinePayloadManifest -PayloadRoot $tempRoot|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Path traversal was not rejected."}
 Write-Host "Offline payload manifest integrity tests passed."
}finally{if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue}}
