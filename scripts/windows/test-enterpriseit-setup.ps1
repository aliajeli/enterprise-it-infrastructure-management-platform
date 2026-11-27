$ErrorActionPreference="Stop"
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$project=Join-Path $repoRoot "apps\api\windows\setup\EnterpriseIT.Setup.csproj"
$publishDir=Join-Path $repoRoot "build\setup"
$setupExe=Join-Path $publishDir "EnterpriseIT.Setup.exe"
$work=Join-Path ([IO.Path]::GetTempPath()) ("enterpriseit-setup-test-"+[guid]::NewGuid().ToString("N"))
$archive=Join-Path $work "payload.zip"
$stagedRoot=Join-Path ([IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))) "EnterpriseIT\0.1.127"
$savedEnv=@{}
foreach($name in @("EIT_SETUP_SCRIPTS_ROOT","EIT_SETUP_PWSH","EIT_SETUP_API_DATABASE_URL","EIT_SETUP_WORKER_DATABASE_URL","EIT_SETUP_BOOTSTRAP_ADMIN_PASSWORD","EIT_SETUP_MIGRATION_PASSWORD","EIT_SETUP_API_PASSWORD","EIT_SETUP_WORKER_PASSWORD")){
 $savedEnv[$name]=[Environment]::GetEnvironmentVariable($name)
}
function Restore-SetupEnvironment {
 foreach($name in @($savedEnv.Keys)){
  if($null -eq $savedEnv[$name]){$null=[Environment]::SetEnvironmentVariable($name,$null)}
  else{[Environment]::SetEnvironmentVariable($name,$savedEnv[$name])}
 }
}
function Invoke-Setup {
 param([string[]]$Arguments)
 $output=& $setupExe @Arguments 2>&1|Out-String
 return [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=$output}
}
try{
 New-Item -ItemType Directory -Path $work -Force|Out-Null

 # Publish the real self-contained single-file Setup.exe (Windows Server CI).
 $publishOutput=& dotnet publish $project --configuration Release --runtime win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -p:DebugSymbols=false --output $publishDir 2>&1|Out-String
 if($LASTEXITCODE -ne 0){throw "Setup.exe publish failed: $publishOutput"}
 if(-not (Test-Path -LiteralPath $setupExe -PathType Leaf) -or (Get-Item -LiteralPath $setupExe).Length -lt 1MB){throw "Setup.exe was not produced as a self-contained executable."}
 [Environment]::SetEnvironmentVariable("EIT_SETUP_SCRIPTS_ROOT",$PSScriptRoot)

 # Fixture archive with a manifest that passes integrity verification.
 Add-Type -AssemblyName System.IO.Compression
 $pkgContent='{"version":"0.1.127"}'
 $pkgBytes=[Text.UTF8Encoding]::new($false).GetBytes($pkgContent)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$pkgHash=[Convert]::ToHexString($sha.ComputeHash($pkgBytes)).ToLowerInvariant()}finally{$sha.Dispose()}
 $manifestContent='{"schemaVersion":1,"hashAlgorithm":"SHA-256","applicationVersion":"0.1.127","files":[{"path":"package.json","sha256":"'+$pkgHash+'","size":'+$pkgBytes.Length+'}]}'
 $stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew)
 try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
   $entry=$zip.CreateEntry("package.json")
   $entryStream=$entry.Open()
   try{$entryStream.Write($pkgBytes,0,$pkgBytes.Length)}finally{$entryStream.Dispose()}
   $manBytes=[Text.UTF8Encoding]::new($false).GetBytes($manifestContent)
   $entry=$zip.CreateEntry("payload.manifest.json")
   $entryStream=$entry.Open()
   try{$entryStream.Write($manBytes,0,$manBytes.Length)}finally{$entryStream.Dispose()}
  }finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash

 # No arguments prints usage and fails closed.
 $result=Invoke-Setup @()
 if($result.ExitCode -eq 0 -or $result.Output -notlike "*EnterpriseIT.Setup modes*"){throw "Setup without arguments must print usage and fail."}

 # Hash verification: valid archive passes, a wrong digest fails closed.
 $result=Invoke-Setup @("verify","--payload",$archive,"--sha256",$hash)
 if($result.ExitCode -ne 0){throw "Setup verify must accept a valid archive and digest: $($result.Output)"}
 $result=Invoke-Setup @("verify","--payload",$archive,"--sha256",("0"*64))
 if($result.ExitCode -eq 0 -or $result.Output -notlike "*digest does not match*"){throw "Setup verify must reject a wrong SHA-256 digest: $($result.Output)"}
 $result=Invoke-Setup @("verify","--payload",(Join-Path $work "missing.zip"),"--sha256",$hash)
 if($result.ExitCode -eq 0){throw "Setup verify must reject a missing payload archive."}

 # Discovery fail-closed branches: bogus pwsh override and bogus scripts root.
 [Environment]::SetEnvironmentVariable("EIT_SETUP_PWSH",(Join-Path $work "missing-pwsh.exe"))
 $result=Invoke-Setup @("verify","--payload",$archive,"--sha256",$hash)
 if($result.ExitCode -eq 0 -or $result.Output -notlike "*pwsh override*"){throw "Setup must fail closed when the pwsh override does not exist: $($result.Output)"}
 [Environment]::SetEnvironmentVariable("EIT_SETUP_PWSH",$null)
 [Environment]::SetEnvironmentVariable("EIT_SETUP_SCRIPTS_ROOT",(Join-Path $work "no-scripts"))
 $result=Invoke-Setup @("verify","--payload",$archive,"--sha256",$hash)
 if($result.ExitCode -eq 0 -or $result.Output -notlike "*scripts were not found*"){throw "Setup must fail closed when the scripts root is incomplete: $($result.Output)"}
 [Environment]::SetEnvironmentVariable("EIT_SETUP_SCRIPTS_ROOT",$PSScriptRoot)

 # Install input gates: connection URLs and a complete bootstrap credential
 # set are required before anything is spawned.
 [Environment]::SetEnvironmentVariable("EIT_SETUP_API_DATABASE_URL",$null)
 [Environment]::SetEnvironmentVariable("EIT_SETUP_WORKER_DATABASE_URL",$null)
 [Environment]::SetEnvironmentVariable("EIT_SETUP_BOOTSTRAP_ADMIN_PASSWORD",$null)
 [Environment]::SetEnvironmentVariable("EIT_SETUP_MIGRATION_PASSWORD",$null)
 [Environment]::SetEnvironmentVariable("EIT_SETUP_API_PASSWORD",$null)
 [Environment]::SetEnvironmentVariable("EIT_SETUP_WORKER_PASSWORD",$null)
 $result=Invoke-Setup @("install","--payload",$archive,"--sha256",$hash,"--edge-bind-address","192.0.2.10","--edge-tls-hostname","it.example.internal","--edge-certificate-thumbprint",("A"*40),"--min-free-space-gb","1")
 if($result.ExitCode -eq 0 -or $result.Output -notlike "*Separate SecureString API and Worker database URLs*"){throw "Setup install must reject missing database URLs: $($result.Output)"}
 [Environment]::SetEnvironmentVariable("EIT_SETUP_API_DATABASE_URL","unused")
 [Environment]::SetEnvironmentVariable("EIT_SETUP_WORKER_DATABASE_URL","unused")
 $result=Invoke-Setup @("install","--payload",$archive,"--sha256",$hash,"--edge-bind-address","192.0.2.10","--edge-tls-hostname","it.example.internal","--edge-certificate-thumbprint",("A"*40),"--bootstrap-admin-user","platform_admin","--min-free-space-gb","1")
 if($result.ExitCode -eq 0 -or $result.Output -notlike "*Bootstrap requires admin, migration, API runtime and Worker runtime SecureString passwords*"){throw "Setup install must reject an incomplete bootstrap credential set: $($result.Output)"}
 foreach($name in @("EIT_SETUP_API_DATABASE_URL","EIT_SETUP_WORKER_DATABASE_URL","EIT_SETUP_BOOTSTRAP_ADMIN_PASSWORD","EIT_SETUP_MIGRATION_PASSWORD","EIT_SETUP_API_PASSWORD","EIT_SETUP_WORKER_PASSWORD")){[Environment]::SetEnvironmentVariable($name,$null)}

 # Integrated install through Setup.exe: stages the immutable version and
 # fails closed at orchestration preflight, retaining the staged root.
 [Environment]::SetEnvironmentVariable("EIT_SETUP_API_DATABASE_URL","unused")
 [Environment]::SetEnvironmentVariable("EIT_SETUP_WORKER_DATABASE_URL","unused")
 if(Test-Path -LiteralPath $stagedRoot){Remove-Item -LiteralPath $stagedRoot -Recurse -Force}
 $result=Invoke-Setup @("install","--payload",$archive,"--sha256",$hash,"--edge-bind-address","192.0.2.10","--edge-tls-hostname","it.example.internal","--edge-certificate-thumbprint",("A"*40),"--min-free-space-gb","1")
 if($result.ExitCode -eq 0 -or $result.Output -notlike "*was staged at*service orchestration failed*"){throw "Setup install must stage and then fail closed at orchestration preflight: $($result.Output)"}
 if(-not (Test-Path -LiteralPath $stagedRoot)){throw "Setup install must retain the staged versioned root."}
 if($result.Output -match "unused"){throw "Setup must redact secret material from relayed output."}

 # Integrated uninstall through Setup.exe removes the staged root.
 $result=Invoke-Setup @("uninstall","--install-root",$stagedRoot)
 if($result.ExitCode -ne 0 -or (Test-Path -LiteralPath $stagedRoot)){throw "Setup uninstall must remove the staged root: $($result.Output)"}
 $result=Invoke-Setup @("uninstall","--install-root",(Join-Path $work "not-program-files"))
 if($result.ExitCode -eq 0){throw "Setup uninstall must reject a non-Program Files install root."}

 Write-Host "EnterpriseIT Setup.exe publish, verification and install/uninstall tests passed."
}finally{
 Restore-SetupEnvironment
 if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
 if(Test-Path -LiteralPath $stagedRoot){Remove-Item -LiteralPath $stagedRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
