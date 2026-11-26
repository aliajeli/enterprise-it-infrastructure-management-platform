$ErrorActionPreference="Stop"
$scriptPath=Join-Path $PSScriptRoot "uninstall-offline-payload.ps1"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
# Version 9.9.9 is reserved for this fixture: product versions are 0.1.x.
$fixtureRoot=Join-Path $pf "EnterpriseIT\9.9.9"
$fixtureData=Join-Path $env:TEMP ("enterpriseit-uninstall-data-"+[guid]::NewGuid().ToString("N"))
$fixtureServices=@("EnterpriseITApi","EnterpriseITWeb","EnterpriseITPostgreSQLBootstrap")
function Remove-FixtureServices {
 foreach($name in $fixtureServices){
  if($null -ne (Get-CimInstance Win32_Service -Filter ("Name='"+$name+"'") -ErrorAction SilentlyContinue)){& sc.exe delete $name|Out-Null}
 }
}
function New-FixtureInstallRoot {
 New-Item -ItemType Directory -Path $fixtureRoot -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $fixtureRoot "payload.marker"),"fixture")
}
try{
 Remove-FixtureServices
 if(Test-Path -LiteralPath $fixtureRoot){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force}

 # Fail-closed shape checks: wrong location, non-versioned path and a
 # missing root must all be rejected before any service or file action.
 foreach($case in @(
  @{Root=(Join-Path $env:TEMP "enterpriseit-not-program-files");Pattern="*beneath Program Files*"},
  @{Root=(Join-Path $pf "EnterpriseIT\not-semver");Pattern="*versioned Program Files payload*"},
  @{Root=$fixtureRoot;Pattern="*does not exist; nothing to uninstall*"}
 )){
  $rejected=$false
  try{& $scriptPath -InstallRoot $case.Root -Confirm:$false|Out-Null}catch{$rejected=$_.Exception.Message -like $case.Pattern}
  if(-not $rejected){throw "Uninstall must reject '$($case.Root)' with: $($case.Pattern)"}
 }

 # WhatIf on a valid root: reports the plan without removing anything.
 New-FixtureInstallRoot
 $whatIf=& $scriptPath -InstallRoot $fixtureRoot -WhatIf|ConvertFrom-Json
 if($whatIf.status -ne "whatif" -or $whatIf.installRootRemoved -or -not (Test-Path -LiteralPath $fixtureRoot)){throw "Uninstall WhatIf must not remove the install root."}
 if(@($whatIf.servicesToRemove).Count -ne 0){throw "Uninstall WhatIf must report no managed services for a service-less root."}

 # Plain uninstall with no managed services: removes only the versioned
 # directory; no ProgramData state is touched without -PurgeData.
 $plain=& $scriptPath -InstallRoot $fixtureRoot -Confirm:$false|ConvertFrom-Json
 if($plain.status -ne "ok" -or -not $plain.installRootRemoved -or (Test-Path -LiteralPath $fixtureRoot)){throw "Plain uninstall must remove the versioned install root."}
 if(@($plain.servicesRemoved).Count -ne 0 -or $plain.dataPurged){throw "Plain uninstall must not remove services it never found nor purge data."}

 # Foreign-service refusal: a managed service name whose binary is outside
 # the install root must block the whole uninstall, untouched.
 New-FixtureInstallRoot
 & sc.exe create "EnterpriseITWeb" binPath= "C:\Windows\System32\cmd.exe" start= demand|Out-Null
 if($LASTEXITCODE -ne 0){throw "Could not create the foreign-service fixture."}
 $foreignRejected=$false
 try{& $scriptPath -InstallRoot $fixtureRoot -Confirm:$false|Out-Null}catch{$foreignRejected=$_.Exception.Message -like "*does not belong to install root*refusing to modify it*"}
 if(-not $foreignRejected){throw "Uninstall must refuse a managed service that does not belong to the install root."}
 if($null -eq (Get-CimInstance Win32_Service -Filter "Name='EnterpriseITWeb'" -ErrorAction SilentlyContinue)){throw "Foreign service must remain untouched after refusal."}
 if(-not (Test-Path -LiteralPath $fixtureRoot)){throw "Install root must remain after the foreign-service refusal."}
 & sc.exe delete "EnterpriseITWeb"|Out-Null
 if($null -ne (Get-CimInstance Win32_Service -Filter "Name='EnterpriseITWeb'" -ErrorAction SilentlyContinue)){throw "Could not clean the foreign-service fixture."}

 # Owned services: services whose binPath is inside the root are stopped
 # (they were never started here), deleted in reverse start order, and the
 # root is removed.
 New-FixtureInstallRoot
 & sc.exe create "EnterpriseITApi" binPath= (Join-Path $fixtureRoot "EnterpriseIT.ApiServiceHost.exe") start= demand|Out-Null
 if($LASTEXITCODE -ne 0){throw "Could not create the owned API service fixture."}
 & sc.exe create "EnterpriseITPostgreSQLBootstrap" binPath= (Join-Path $fixtureRoot "EnterpriseIT.PostgreSQLBootstrap.exe") start= demand|Out-Null
 if($LASTEXITCODE -ne 0){throw "Could not create the owned bootstrap service fixture."}
 $owned=& $scriptPath -InstallRoot $fixtureRoot -Confirm:$false|ConvertFrom-Json
 if($owned.status -ne "ok" -or -not $owned.installRootRemoved){throw "Uninstall must remove the install root after deleting owned services."}
 $removedNames=@($owned.servicesRemoved)
 if($removedNames -join "," -ne "EnterpriseITApi,EnterpriseITPostgreSQLBootstrap"){throw "Owned services must be removed in reverse start order, got: $($removedNames -join ',')"}
 foreach($name in @("EnterpriseITApi","EnterpriseITPostgreSQLBootstrap")){
  if($null -ne (Get-CimInstance Win32_Service -Filter ("Name='"+$name+"'") -ErrorAction SilentlyContinue)){throw "Owned service '$name' must be deleted by uninstall."}
 }

 # Data preservation by default; purge only with the explicit switch.
 New-FixtureInstallRoot
 New-Item -ItemType Directory -Path $fixtureData -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $fixtureData "PG_VERSION"),"18")
 $kept=& $scriptPath -InstallRoot $fixtureRoot -DataRoot $fixtureData -Confirm:$false|ConvertFrom-Json
 if(-not $kept.dataRootPreserved -or $kept.dataPurged -or -not (Test-Path -LiteralPath (Join-Path $fixtureData "PG_VERSION"))){throw "Uninstall must preserve the data directory without -PurgeData."}
 New-FixtureInstallRoot
 $purged=& $scriptPath -InstallRoot $fixtureRoot -DataRoot $fixtureData -PurgeData -Confirm:$false|ConvertFrom-Json
 if(-not $purged.dataPurged -or (Test-Path -LiteralPath $fixtureData)){throw "Uninstall must purge the data directory only with -PurgeData."}

 # Reparse-point child inside the install root blocks directory removal.
 New-FixtureInstallRoot
 $junctionTarget=Join-Path $env:TEMP ("enterpriseit-uninstall-junction-"+[guid]::NewGuid().ToString("N"))
 New-Item -ItemType Directory -Path $junctionTarget -Force|Out-Null
 $junctionChild=Join-Path $fixtureRoot "state"
 $junctionOutput=& cmd.exe /c "mklink /J `"$junctionChild`" `"$junctionTarget`""
 if($LASTEXITCODE -ne 0){throw "Could not create the reparse fixture: $junctionOutput"}
 $reparseRejected=$false
 try{& $scriptPath -InstallRoot $fixtureRoot -Confirm:$false|Out-Null}catch{$reparseRejected=$_.Exception.Message -like "*reparse-point children*refusing to remove it*"}
 if(-not $reparseRejected){throw "Uninstall must refuse an install root that contains reparse-point children."}
 if(-not (Test-Path -LiteralPath $fixtureRoot)){throw "Install root must remain after the reparse refusal."}
 Remove-Item -LiteralPath (Join-Path $fixtureRoot "state") -Force
 Remove-Item -LiteralPath $junctionTarget -Recurse -Force

 # Integrated install -> uninstall round trip: a real install verifies the
 # archive, builds a passing manifest, stages the immutable versioned root,
 # reaches orchestration and fails closed there (the fixture payload cannot
 # pass orchestration preflight), retains the staged root as designed, and
 # a real uninstall then removes it. Without bootstrap credentials the
 # first-install fail-closed stop inside orchestration stays authoritative.
 Add-Type -AssemblyName System.IO.Compression
 $roundtripArchive=Join-Path $env:TEMP ("enterpriseit-roundtrip-"+[guid]::NewGuid().ToString("N")+".zip")
 $roundtripRoot=Join-Path $pf "EnterpriseIT\0.1.128"
 $pkgContent='{"version":"0.1.128"}'
 $pkgBytes=[Text.UTF8Encoding]::new($false).GetBytes($pkgContent)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$pkgHash=[Convert]::ToHexString($sha.ComputeHash($pkgBytes)).ToLowerInvariant()}finally{$sha.Dispose()}
 $manifestContent='{"schemaVersion":1,"hashAlgorithm":"SHA-256","applicationVersion":"0.1.128","files":[{"path":"package.json","sha256":"'+$pkgHash+'","size":'+$pkgBytes.Length+'}]}'
 $stream=[IO.File]::Open($roundtripArchive,[IO.FileMode]::CreateNew)
 try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
   $pkgEntry=$zip.CreateEntry("package.json")
   $entryStream=$pkgEntry.Open()
   try{$entryStream.Write($pkgBytes,0,$pkgBytes.Length)}finally{$entryStream.Dispose()}
   $manBytes=[Text.UTF8Encoding]::new($false).GetBytes($manifestContent)
   $manEntry=$zip.CreateEntry("payload.manifest.json")
   $entryStream=$manEntry.Open()
   try{$entryStream.Write($manBytes,0,$manBytes.Length)}finally{$entryStream.Dispose()}
  }finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $roundtripHash=(Get-FileHash -LiteralPath $roundtripArchive -Algorithm SHA256).Hash
 if(Test-Path -LiteralPath $roundtripRoot){Remove-Item -LiteralPath $roundtripRoot -Recurse -Force}
 $roundtripUrls=ConvertTo-SecureString 'unused' -AsPlainText -Force
 $installFailed=$false
 $installMessage=""
 try{
  & (Join-Path $PSScriptRoot "install-offline-payload.ps1") -PayloadArchive $roundtripArchive -ExpectedSha256 $roundtripHash -ApiDatabaseUrl $roundtripUrls -WorkerDatabaseUrl $roundtripUrls -EdgeBindAddress "192.0.2.10" -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40) -MinimumFreeSpaceGB 1 -Confirm:$false|Out-Null
 }catch{
  $installFailed=$true
  $installMessage=$_.Exception.Message
 }
 if(-not $installFailed -or $installMessage -notlike "*was staged at*service orchestration failed*"){
  throw "Integrated install must stage the payload and fail closed at orchestration preflight; got: $installMessage"
 }
 if(-not (Test-Path -LiteralPath $roundtripRoot)){throw "Integrated install must retain the staged versioned root for uninstall."}
 $roundtripUninstall=& (Join-Path $PSScriptRoot "uninstall-offline-payload.ps1") -InstallRoot $roundtripRoot -Confirm:$false|ConvertFrom-Json
 if($roundtripUninstall.status -ne "ok" -or -not $roundtripUninstall.installRootRemoved -or (Test-Path -LiteralPath $roundtripRoot)){throw "Integrated uninstall must remove the staged root after the failed orchestration."}

 Write-Host "Offline payload uninstall policy tests passed."
}finally{
 Remove-FixtureServices
 if(Test-Path -LiteralPath $fixtureRoot){
  $item=Get-Item -LiteralPath $fixtureRoot -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue}
 }
 if(Test-Path -LiteralPath $fixtureData){Remove-Item -LiteralPath $fixtureData -Recurse -Force -ErrorAction SilentlyContinue}
 $leftover=Join-Path $env:TEMP "enterpriseit-uninstall-junction-*"
 Get-Item -Path $leftover -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
 $roundtripRoot=Join-Path $pf "EnterpriseIT\0.1.128"
 if(Test-Path -LiteralPath $roundtripRoot){Remove-Item -LiteralPath $roundtripRoot -Recurse -Force -ErrorAction SilentlyContinue}
 $roundtripArchive=Join-Path $env:TEMP "enterpriseit-roundtrip-*.zip"
 Get-Item -Path $roundtripArchive -ErrorAction SilentlyContinue|Remove-Item -Force -ErrorAction SilentlyContinue
}
