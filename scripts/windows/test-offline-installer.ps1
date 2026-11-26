$ErrorActionPreference="Stop"
$scriptPath=Join-Path $PSScriptRoot 'install-offline-payload.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('enterpriseit-installer-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force|Out-Null
try{
 Add-Type -AssemblyName System.IO.Compression
 $valid=Join-Path $root 'valid.zip'
 $stream=[IO.File]::Open($valid,[IO.FileMode]::CreateNew)
 try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
   foreach($item in @(@('package.json','{"version":"0.1.128"}'),@('payload.manifest.json','{"applicationVersion":"0.1.128"}'))){
    $entry=$zip.CreateEntry($item[0]);$writer=[IO.StreamWriter]::new($entry.Open())
    try{$writer.Write($item[1])}finally{$writer.Dispose()}
   }
  }finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $hash=(Get-FileHash -LiteralPath $valid -Algorithm SHA256).Hash
 . $scriptPath -PayloadArchive $valid -ExpectedSha256 $hash
 $plan=Get-OfflineInstallerPlan -PayloadArchive $valid -ExpectedSha256 $hash
 if($plan.EntryCount -ne 2){throw 'Valid archive entry count was not preserved.'}
 $dry=& $scriptPath -PayloadArchive $valid -ExpectedSha256 $hash -WhatIf | ConvertFrom-Json
 if($dry.EntryCount -ne 2){throw 'Installer WhatIf must remain available for archive inspection.'}
 if($dry.bootstrapRequested){throw 'Installer WhatIf must report no database bootstrap when no admin user is supplied.'}
 # Capability gate (G3 replacement): incomplete inputs must be rejected
 # before staging, and the orchestration entry point must exist beside the
 # installer. Full-input acceptance is covered by the integrated round trip.
 $blocked=$false
 try{& $scriptPath -PayloadArchive $valid -ExpectedSha256 $hash -Confirm:$false|Out-Null}catch{
  $blocked=$_.Exception.Message -like '*Separate SecureString API and Worker database URLs*'
 }
 if(-not $blocked){throw 'Installer must reject missing database URLs before staging an immutable payload.'}
 $edgeSecret=ConvertTo-SecureString 'unused' -AsPlainText -Force
 $blocked=$false
 try{& $scriptPath -PayloadArchive $valid -ExpectedSha256 $hash -ApiDatabaseUrl $edgeSecret -WorkerDatabaseUrl $edgeSecret -Confirm:$false|Out-Null}catch{
  $blocked=$_.Exception.Message -like '*Edge bind address, TLS hostname and certificate thumbprint are required*'
 }
 if(-not $blocked){throw 'Installer must reject missing Edge inputs before staging.'}
 $emptyEntryRoot=Join-Path $env:TEMP ("enterpriseit-installer-entry-"+[guid]::NewGuid().ToString("N"))
 New-Item -ItemType Directory -Path $emptyEntryRoot|Out-Null
 try{
  $blocked=$false
  try{Assert-OfflineInstallerCapability -ApiDatabaseUrl $edgeSecret -WorkerDatabaseUrl $edgeSecret -EdgeBindAddress '192.0.2.10' -EdgeTlsHostname 'it.example.internal' -EdgeCertificateThumbprint ('A'*40) -InstallerScriptRoot $emptyEntryRoot|Out-Null}catch{
   $blocked=$_.Exception.Message -like '*orchestration entry point is missing*no files or services were changed*'
  }
  if(-not $blocked){throw 'Installer capability gate must reject a payload without the orchestration entry point.'}
 }finally{
  if(Test-Path -LiteralPath $emptyEntryRoot){Remove-Item -LiteralPath $emptyEntryRoot -Recurse -Force -ErrorAction SilentlyContinue}
 }
 $accepted=$true
 try{Assert-OfflineInstallerCapability -ApiDatabaseUrl $edgeSecret -WorkerDatabaseUrl $edgeSecret -EdgeBindAddress '192.0.2.10' -EdgeTlsHostname 'it.example.internal' -EdgeCertificateThumbprint ('A'*40)|Out-Null}catch{$accepted=$false}
 if(-not $accepted){throw 'Installer capability gate must accept complete inputs with the orchestration entry point present.'}

 # First-install database bootstrap inputs must be received and validated by
 # the installer itself - even in WhatIf preview mode - and reported through
 # the plan so a fresh PostgreSQL install is completable from installer
 # inputs alone. Secrets must never appear in any plan or message.
 $bootstrapSecret='installer-bootstrap-secret-49'
 $bootstrapSecure=ConvertTo-SecureString $bootstrapSecret -AsPlainText -Force
 $incompleteRejected=$false
 try{& $scriptPath -PayloadArchive $valid -ExpectedSha256 $hash -BootstrapAdminUser 'platform_admin' -WhatIf|Out-Null}catch{
  if($_.Exception.Message -match [regex]::Escape($bootstrapSecret)){throw 'Installer bootstrap validation exposed a secret.'}
  $incompleteRejected=$_.Exception.Message -like '*Bootstrap requires admin, migration, API runtime and Worker runtime SecureString passwords*'
 }
 if(-not $incompleteRejected){throw 'Installer must reject an incomplete bootstrap credential set before any staging, including in WhatIf mode.'}
 $bootstrapDry=& $scriptPath -PayloadArchive $valid -ExpectedSha256 $hash -BootstrapAdminUser 'platform_admin' -BootstrapAdminPassword $bootstrapSecure -MigrationPassword $bootstrapSecure -ApiRuntimePassword $bootstrapSecure -WorkerRuntimePassword $bootstrapSecure -WhatIf|ConvertFrom-Json
 if(-not $bootstrapDry.bootstrapRequested){throw 'Installer WhatIf must report that a database bootstrap was requested.'}
 if(($bootstrapDry|ConvertTo-Json -Depth 5) -match [regex]::Escape($bootstrapSecret)){throw 'Installer WhatIf plan must not contain bootstrap secrets.'}
 # The mutating installer path must forward every bootstrap input to the
 # orchestration entry point that builds the bootstrap capability set.
 $installerSource=Get-Content -LiteralPath $scriptPath -Raw
 foreach($forwarded in @('-BootstrapAdminUser $BootstrapAdminUser','-BootstrapAdminPassword $BootstrapAdminPassword','-DatabaseName $DatabaseName','-SchemaOwnerRole $SchemaOwnerRole','-MigrationRole $MigrationRole','-MigrationPassword $MigrationPassword','-ApiRuntimeRole $ApiRuntimeRole','-ApiRuntimePassword $ApiRuntimePassword','-WorkerRuntimeRole $WorkerRuntimeRole','-WorkerRuntimePassword $WorkerRuntimePassword')){
  if($installerSource -notmatch [regex]::Escape($forwarded)){throw "Installer must forward $forwarded to the orchestration entry point."}
 }
 $readLock=Open-OfflineArchiveReadLock -ArchivePath $valid
 try{
  # Validation must still work while replacement/write attempts are denied.
  $lockedPlan=Get-OfflineInstallerPlan -PayloadArchive $valid -ExpectedSha256 $hash -ArchiveHandle $readLock
  if($lockedPlan.EntryCount -ne 2){throw 'Locked archive validation failed.'}
  # A path replacement or renamed ancestor must not change what is hashed or
  # inspected: the verified content comes only from the retained file handle.
  $missingPath=Join-Path $root 'does-not-exist.zip'
  $sameHandlePlan=Get-OfflineInstallerPlan -PayloadArchive $missingPath -ExpectedSha256 $hash -ArchiveHandle $readLock
  if($sameHandlePlan.EntryCount -ne 2){throw 'Archive verification unexpectedly reopened its path.'}
  $writeRejected=$false
  try{$writer=[IO.File]::Open($valid,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::Read);$writer.Dispose()}catch{$writeRejected=$true}
  if(-not $writeRejected){throw 'Archive write was accepted while validation held its lock.'}
  $deleteRejected=$false
  try{[IO.File]::Move($valid,(Join-Path $root 'moved.zip'))}catch{$deleteRejected=$true}
  if(-not $deleteRejected){throw 'Archive replacement was accepted while validation held its lock.'}
 }finally{$readLock.Dispose()}
 # Exercise ZIP-entry reading independently; the mutating installer path remains disabled.
 $file=[IO.File]::OpenRead($valid)
 try{
  $zip=[IO.Compression.ZipArchive]::new($file,[IO.Compression.ZipArchiveMode]::Read,$true)
  try{
   $metadata=Read-BoundedOfflineZipText -Entry ($zip.GetEntry('package.json')) -MaximumBytes 1024 | ConvertFrom-Json
   if($metadata.version -ne '0.1.128'){throw 'Bounded ZIP metadata read failed.'}
   $bounded=$false;try{Read-BoundedOfflineZipText -Entry ($zip.GetEntry('package.json')) -MaximumBytes 1|Out-Null}catch{$bounded=$true}
   if(-not $bounded){throw 'Oversized declared ZIP entry was accepted.'}
  }finally{$zip.Dispose()}
 }finally{$file.Dispose()}
 # Actual decompressed bytes are bounded independently of ZIP metadata.
 $testInput=[IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('01234567890'))
 try{
  $bounded=$false
  try{Read-BoundedOfflineUtf8Stream -InputStream $testInput -MaximumBytes 10|Out-Null}catch{$bounded=$true}
  if(-not $bounded){throw 'Metadata stream exceeding the actual byte limit was accepted.'}
 }finally{$testInput.Dispose()}
 $testInput=[IO.MemoryStream]::new([byte[]](0xef,0xbb,0xbf,0x6f,0x6b))
 try{if((Read-BoundedOfflineUtf8Stream -InputStream $testInput -MaximumBytes 5) -cne 'ok'){throw 'UTF-8 BOM handling failed.'}}finally{$testInput.Dispose()}
 $testInput=[IO.MemoryStream]::new([byte[]](0xff))
 try{
  $invalid=$false;try{Read-BoundedOfflineUtf8Stream -InputStream $testInput -MaximumBytes 1|Out-Null}catch{$invalid=$true}
  if(-not $invalid){throw 'Invalid UTF-8 metadata was accepted.'}
 }finally{$testInput.Dispose()}
 # A highly compressed metadata entry is still rejected based on expanded size.
 $oversized=Join-Path $root 'oversized-package.zip'
 $stream=[IO.File]::Open($oversized,[IO.FileMode]::CreateNew)
 try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
   $entry=$zip.CreateEntry('package.json');$data=$entry.Open()
   try{$chunk=[byte[]]::new(65536);for($i=0;$i -lt 16;$i++){$data.Write($chunk,0,$chunk.Length)};$data.WriteByte(0)}finally{$data.Dispose()}
   $entry=$zip.CreateEntry('payload.manifest.json');$writer=[IO.StreamWriter]::new($entry.Open())
   try{$writer.Write('{}')}finally{$writer.Dispose()}
  }finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $oversizedHash=(Get-FileHash -LiteralPath $oversized -Algorithm SHA256).Hash
 $bounded=$false;try{Test-OfflineInstallerArchive -ArchivePath $oversized -ExpectedSha256 $oversizedHash|Out-Null}catch{$bounded=$true}
 if(-not $bounded){throw 'Oversized compressed package metadata was accepted.'}
 # Metadata names are canonical because ZipArchive.GetEntry is case-sensitive.
 $noncanonical=Join-Path $root 'noncanonical.zip'
 $stream=[IO.File]::Open($noncanonical,[IO.FileMode]::CreateNew)
 try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{foreach($name in @('PACKAGE.JSON','payload.manifest.json')){$entry=$zip.CreateEntry($name);$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write('{}')}finally{$writer.Dispose()}}}finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $noncanonicalHash=(Get-FileHash -LiteralPath $noncanonical -Algorithm SHA256).Hash
 $rejected=$false;try{Test-OfflineInstallerArchive -ArchivePath $noncanonical -ExpectedSha256 $noncanonicalHash|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw 'Noncanonical metadata name was accepted.'}
 $rejected=$false;try{Test-OfflineInstallerArchive -ArchivePath $valid -ExpectedSha256 ('0'*64)|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw 'Archive with an incorrect trusted digest was accepted.'}
 $unsafe=Join-Path $root 'unsafe.zip'
 $stream=[IO.File]::Open($unsafe,[IO.FileMode]::CreateNew)
 try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
   foreach($name in @('package.json','payload.manifest.json','../escape.txt')){
    $entry=$zip.CreateEntry($name);$writer=[IO.StreamWriter]::new($entry.Open())
    try{$writer.Write('{}')}finally{$writer.Dispose()}
   }
  }finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $unsafeHash=(Get-FileHash -LiteralPath $unsafe -Algorithm SHA256).Hash
 $rejected=$false;try{Test-OfflineInstallerArchive -ArchivePath $unsafe -ExpectedSha256 $unsafeHash|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw 'ZIP path traversal entry was accepted.'}
 $windowsUnsafe=Join-Path $root 'windows-unsafe.zip'
 $stream=[IO.File]::Open($windowsUnsafe,[IO.FileMode]::CreateNew)
 try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
   foreach($item in @(@('package.json','{}'),@('payload.manifest.json','{}'),@('folder/file:stream','x'))){
    $entry=$zip.CreateEntry($item[0]);$writer=[IO.StreamWriter]::new($entry.Open())
    try{$writer.Write($item[1])}finally{$writer.Dispose()}
   }
  }finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $windowsUnsafeHash=(Get-FileHash -LiteralPath $windowsUnsafe -Algorithm SHA256).Hash
 $rejected=$false;try{Test-OfflineInstallerArchive -ArchivePath $windowsUnsafe -ExpectedSha256 $windowsUnsafeHash|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw 'ZIP alternate-data-stream path was accepted.'}
 foreach($unsafeName in @('CON.txt','folder/trailing.','folder/trailing ',('COM'+[char]0x00b9+'.txt'),('folder/LPT'+[char]0x00b2),('com'+[char]0x00b3))){
  $casePath=Join-Path $root ('unsafe-'+[guid]::NewGuid().ToString('N')+'.zip')
  $stream=[IO.File]::Open($casePath,[IO.FileMode]::CreateNew)
  try{
   $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
   try{
    foreach($name in @('package.json','payload.manifest.json',$unsafeName)){
     $entry=$zip.CreateEntry($name);$writer=[IO.StreamWriter]::new($entry.Open())
     try{$writer.Write('{}')}finally{$writer.Dispose()}
    }
   }finally{$zip.Dispose()}
  }finally{$stream.Dispose()}
  $caseHash=(Get-FileHash -LiteralPath $casePath -Algorithm SHA256).Hash
  $rejected=$false;try{Test-OfflineInstallerArchive -ArchivePath $casePath -ExpectedSha256 $caseHash|Out-Null}catch{$rejected=$true}
  if(-not $rejected){throw "ZIP Windows-invalid path was accepted: $unsafeName"}
 }
 # Reject file/directory prefix collisions in either archive order and with
 # Windows case folding. Explicit parent directories remain valid.
 foreach($case in @(
  @{Names=@('A','a/child.txt')},
  @{Names=@('a/child.txt','A')},
  @{Names=@('folder/child/grandchild','FOLDER/CHILD')}
 )){
  $casePath=Join-Path $root ('prefix-'+[guid]::NewGuid().ToString('N')+'.zip')
  $stream=[IO.File]::Open($casePath,[IO.FileMode]::CreateNew)
  try{
   $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
   try{foreach($name in (@('package.json','payload.manifest.json')+$case.Names)){$entry=$zip.CreateEntry($name);$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write('{}')}finally{$writer.Dispose()}}}finally{$zip.Dispose()}
  }finally{$stream.Dispose()}
  $caseHash=(Get-FileHash -LiteralPath $casePath -Algorithm SHA256).Hash
  $rejected=$false;try{Test-OfflineInstallerArchive -ArchivePath $casePath -ExpectedSha256 $caseHash|Out-Null}catch{$rejected=$_.Exception.Message -like '*ancestor directory*'}
  if(-not $rejected){throw 'ZIP file/directory prefix collision was accepted or rejected for an unrelated reason.'}
 }
 $directoryCase=Join-Path $root 'explicit-directory.zip'
 $stream=[IO.File]::Open($directoryCase,[IO.FileMode]::CreateNew)
 try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
   [void]$zip.CreateEntry('folder/')
   foreach($name in @('package.json','payload.manifest.json','folder/child.txt')){$entry=$zip.CreateEntry($name);$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write('{}')}finally{$writer.Dispose()}}
  }finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $caseHash=(Get-FileHash -LiteralPath $directoryCase -Algorithm SHA256).Hash
 $casePlan=Test-OfflineInstallerArchive -ArchivePath $directoryCase -ExpectedSha256 $caseHash
 if($casePlan.entryCount -ne 4){throw 'Valid explicit parent directory was rejected.'}
 Write-Output 'Offline installer archive validation tests passed.'
}finally{if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}}
