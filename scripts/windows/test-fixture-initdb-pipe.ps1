# Synthetic initdb stand-in. NEVER used to initialize a real cluster.
$ErrorActionPreference='Stop'
$expected='synthetic-initdb-secret-42'
if(([Environment]::GetCommandLineArgs() -join ' ').Contains($expected)){exit 11}
if($args -contains '--fixture-timeout'){Start-Sleep -Seconds 15;exit 12}
$childArgument=@($args|Where-Object{$_ -like '--fixture-child=*'})
if($childArgument.Count -eq 1){
 try{
  $childReader=[IO.StreamReader]::new($childArgument[0].Substring('--fixture-child='.Length))
  try{$null=$childReader.ReadLine()}finally{$childReader.Dispose()}
 }catch{}
 exit 0
}
$argument=@($args|Where-Object{$_ -like '--pwfile=*'})
if($argument.Count -ne 1){exit 13}
$path=$argument[0].Substring('--pwfile='.Length)
if(-not $path.StartsWith('\\.\pipe\enterpriseit-initdb-')){exit 14}
if($args -contains '--fixture-wrong-client'){
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=Join-Path $PSHOME 'pwsh.exe'
 foreach($a in @('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,('--fixture-child='+$path))){$psi.ArgumentList.Add($a)}
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $child=[Diagnostics.Process]::Start($psi)
 $child.WaitForExit()
 exit 0
}
try{
 $reader=[IO.StreamReader]::new($path,[Text.UTF8Encoding]::new($false,$true))
 try{$line=$reader.ReadLine()}finally{$reader.Dispose()}
 if($line -cne $expected){exit 15}
 # Intentionally echo synthetic material to prove the parent never forwards
 # child output into logs or its return value.
 [Console]::Out.Write($line)
 [Console]::Error.Write($line)
 exit 0
}catch{exit 16}
