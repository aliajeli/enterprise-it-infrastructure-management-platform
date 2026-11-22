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
   foreach($item in @(@('package.json','{"version":"0.1.122"}'),@('payload.manifest.json','{"applicationVersion":"0.1.122"}'))){
    $entry=$zip.CreateEntry($item[0]);$writer=[IO.StreamWriter]::new($entry.Open())
    try{$writer.Write($item[1])}finally{$writer.Dispose()}
   }
  }finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $hash=(Get-FileHash -LiteralPath $valid -Algorithm SHA256).Hash
 . $scriptPath -PayloadArchive $valid -ExpectedSha256 $hash
 $plan=Get-OfflineInstallerPlan -PayloadArchive $valid -ExpectedSha256 $hash
 if($plan.EntryCount -ne 2){throw 'Valid archive entry count was not preserved.'}
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
 foreach($unsafeName in @('CON.txt','folder/trailing.','folder/trailing ')){
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
 Write-Output 'Offline installer archive validation tests passed.'
}finally{if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}}
