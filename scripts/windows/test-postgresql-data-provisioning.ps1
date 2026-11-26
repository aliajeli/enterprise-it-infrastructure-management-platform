# Native data-directory provisioning policy/integration tests for the dedicated
# PostgreSQL bootstrap executable (NtCreateFile + SECURITY_DESCRIPTOR at
# creation, handle-relative ancestors, reparse/volume/file-ID validation,
# parent-vs-leaf ACL split, identity-checked transactional rollback).
# Runs elevated in CI against synthetic volume-root fixtures so production
# ProgramData ACLs are never modified. Path-based fixture setup below is test
# scaffolding only; the provisioner under test performs no path-based create or
# ACL operation on the data chain.
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$projectDir=Join-Path $repoRoot "apps\api\windows\postgresql-bootstrap"
$project=Join-Path $projectDir "EnterpriseIT.PostgreSQLBootstrap.csproj"
$releaseExe=Join-Path $projectDir "bin\Release\net10.0-windows\EnterpriseIT.PostgreSQLBootstrap.exe"
$releaseDll=Join-Path $projectDir "bin\Release\net10.0-windows\EnterpriseIT.PostgreSQLBootstrap.dll"
if(-not(Test-Path -LiteralPath $releaseExe -PathType Leaf) -and -not(Test-Path -LiteralPath $releaseDll -PathType Leaf)){
 dotnet build $project --configuration Release | Out-Host
 if($LASTEXITCODE -ne 0){throw "Could not build PostgreSQL bootstrap provisioner for tests."}
}
$releasePath=if(Test-Path -LiteralPath $releaseExe -PathType Leaf){$releaseExe}else{$releaseDll}

# Service SIDs are the documented SHA1-of-uppercase-name derivation; compute
# them directly so tests do not depend on SCM state, and cross-check sc showsid
# for the bootstrap name when the SCM responds.
function Get-TestServiceSid([string]$Name){
 $bytes=[Text.Encoding]::Unicode.GetBytes($Name.ToUpperInvariant())
 $sha1=[Security.Cryptography.SHA1]::Create()
 try{$hash=$sha1.ComputeHash($bytes)}finally{$sha1.Dispose()}
 $parts=@()
 for($i=0;$i -lt 5;$i++){$parts+=[BitConverter]::ToUInt32($hash,$i*4).ToString([Globalization.CultureInfo]::InvariantCulture)}
 "S-1-5-80-" + ($parts -join '-')
}
$bootstrapSid=Get-TestServiceSid "EnterpriseITPostgreSQLBootstrap"
$postgresSid=Get-TestServiceSid "EnterpriseITPostgreSQL"
if($bootstrapSid -notmatch '^S-1-5-80-(?:\d+-){4}\d+$' -or $postgresSid -eq $bootstrapSid){throw "Derived test service SIDs are invalid."}
$scOutput=(& sc.exe showsid EnterpriseITPostgreSQLBootstrap 2>&1|Out-String)
if($LASTEXITCODE -eq 0){
 $scMatch=[regex]::Match($scOutput,'S-1-5-80-(?:\d+-){4}\d+')
 if($scMatch.Success -and $scMatch.Value -ne $bootstrapSid){throw "sc showsid disagrees with the derived bootstrap service SID."}
}

function Invoke-Provisioner([string[]]$Arguments,[string]$Executable=$releasePath,[string]$Fault=''){
 $start=[Diagnostics.ProcessStartInfo]::new()
 if($Executable.EndsWith(".dll",[StringComparison]::OrdinalIgnoreCase)){$start.FileName="dotnet";$start.ArgumentList.Add($Executable)}else{$start.FileName=$Executable}
 foreach($a in $Arguments){$start.ArgumentList.Add([string]$a)}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $null=$start.Environment.Remove('ENTERPRISEIT_PG_TEST_FAULT')
 if($Fault){$start.Environment['ENTERPRISEIT_PG_TEST_FAULT']=$Fault}
 $p=[Diagnostics.Process]::Start($start)
 try{
  $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(30000)){try{$p.Kill($true);$p.WaitForExit()}catch{};throw 'Bootstrap provisioner fixture timed out.'}
  [pscustomobject]@{ExitCode=$p.ExitCode;StdOut=$outTask.GetAwaiter().GetResult();StdErr=$errTask.GetAwaiter().GetResult()}
 }finally{$p.Dispose()}
}

# Independent file identity for idempotency assertions (volume serial + 128-bit file ID).
if(-not('EnterpriseIT.ProvisionFileId' -as [type])){
 Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace EnterpriseIT {
 public static class ProvisionFileId {
  [StructLayout(LayoutKind.Sequential)] private struct FileIdInfo { public ulong VolumeSerialNumber, FileIdLow, FileIdHigh; }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="CreateFileW")]
  private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError=true, EntryPoint="GetFileInformationByHandleEx")]
  private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int infoClass, out FileIdInfo info, int size);
  public static string Get(string path) {
   using (var handle = CreateFileW(path, 0x80|0x20000|0x100000, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
    if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
    FileIdInfo id;
    if (!GetFileInformationByHandleEx(handle, 18, out id, Marshal.SizeOf(typeof(FileIdInfo)))) throw new Win32Exception(Marshal.GetLastWin32Error());
    return id.VolumeSerialNumber.ToString("X16") + "-" + id.FileIdLow.ToString("X16") + "-" + id.FileIdHigh.ToString("X16");
   }
  }
 }
}
'@
}

function New-TestRoot([string]$Name){
 $volumeRoot=[IO.Path]::GetPathRoot($env:SystemRoot)
 if(-not $volumeRoot){throw 'Could not resolve the system volume root for provisioning fixtures.'}
 $root=Join-Path $volumeRoot ("EnterpriseIT-PgData-Provision-" + $Name + "-" + [guid]::NewGuid().ToString("N"))
 $pd=Join-Path $root "ProgramData"
 if(Test-Path -LiteralPath $root){throw 'Fixture root collision.'}
 [IO.Directory]::CreateDirectory($root)|Out-Null
 [IO.Directory]::CreateDirectory($pd)|Out-Null
 foreach($path in @($root,$pd)){
  $protectedAcl=Get-Acl -LiteralPath $path
  $protectedAcl.SetAccessRuleProtection($true,$false)
  foreach($sid in @('S-1-5-18','S-1-5-32-544')){
   $identity=[Security.Principal.SecurityIdentifier]::new($sid)
   $rule=[Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
   $protectedAcl.AddAccessRule($rule)
  }
  Set-Acl -LiteralPath $path -AclObject $protectedAcl
 }
 [pscustomobject]@{Root=$root;ProgramData=$pd}
}

function Get-DataPaths([string]$ProgramData){
 $enterprise=Join-Path $ProgramData "EnterpriseIT"
 $postgreSql=Join-Path $enterprise "PostgreSQL"
 $version=Join-Path $postgreSql "18"
 $data=Join-Path $version "data"
 [pscustomobject]@{Enterprise=$enterprise;PostgreSql=$postgreSql;Version=$version;Data=$data}
}

# Exact parent/leaf ACL policy: owner Administrators, protected DACL, exactly
# four explicit OICI allow ACEs (SYSTEM+Administrators FA and both service
# SIDs at RX for parents / Modify-minus-owner for the data leaf).
function Assert-DataAcl([string]$Path,[bool]$Leaf){
 $acl=Get-Acl -LiteralPath $Path
 $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
 if($owner -ne 'S-1-5-32-544' -and $owner -ne 'S-1-5-18'){
  throw "Data-chain owner must be Administrators or SYSTEM (observed owner: $owner): $Path"
 }
 if($acl.AreAccessRulesProtected -ne $true){throw "Data-chain DACL must be protected: $Path"}
 $rules=@($acl.Access)
 if($rules.Count -ne 4){throw "Data-chain DACL must contain exactly four ACEs (observed: $($rules.Count); SDDL: $($acl.Sddl)): $Path"}
 $expectedMask=if($Leaf){0x1301FF}else{0x1200A9}
 $expected=@{'S-1-5-18'=0x1F01FF;'S-1-5-32-544'=0x1F01FF}
 $expected[$bootstrapSid]=$expectedMask
 $expected[$postgresSid]=$expectedMask
 $seen=@{}
 foreach($rule in $rules){
  if($rule.IsInherited){throw "Data-chain ACE must be explicit: $Path"}
  if($rule.AccessControlType -ne 'Allow'){throw "Data-chain ACE must be an allow ACE: $Path"}
  $expectedInheritance=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
  if($rule.InheritanceFlags -ne $expectedInheritance -or $rule.PropagationFlags -ne 'None'){
   throw "Data-chain ACE inheritance must be OICI with no propagation (observed: $($rule.InheritanceFlags)/$($rule.PropagationFlags)): $Path"
  }
  $sid=try{$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value}catch{$rule.IdentityReference.Value}
  if(-not $expected.ContainsKey($sid)){throw "Unexpected ACE principal on the data chain (observed: $sid): $Path"}
  $mask=[int]$rule.FileSystemRights
  if($mask -ne $expected[$sid]){throw "ACE mask mismatch for $sid (observed 0x$($mask.ToString('X8')), expected 0x$($expected[$sid].ToString('X8'))): $Path"}
  if($seen.ContainsKey($sid)){throw "Duplicate ACE for $sid on the data chain: $Path"}
  $seen[$sid]=$true
 }
 if($seen.Count -ne 4){throw "Not all expected principals are present on the data chain: $Path"}
 if((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Data-chain path is a reparse point: $Path"}
}

# 1. Fresh provisioning creates the chain with the exact split ACL policy and
#    never adds, removes or protects any EnterpriseIT ACE.
$t=New-TestRoot "fresh"
try{
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -ne 0 -or $r.StdOut.Trim() -ne 'OK'){throw "Fresh provision failed: $($r.ExitCode) $($r.StdErr)"}
 $p=Get-DataPaths $t.ProgramData
 foreach($path in @($p.Enterprise,$p.PostgreSql,$p.Version,$p.Data)){
  if(-not(Test-Path -LiteralPath $path -PathType Container)){throw "Missing provisioned directory: $path"}
 }
 $enterpriseAcl=Get-Acl -LiteralPath $p.Enterprise
 $explicit=@($enterpriseAcl.Access|Where-Object{-not $_.IsInherited})
 if($explicit.Count -ne 0){throw "Provisioner must not add any ACE to EnterpriseIT (observed explicit ACEs: $($explicit.Count))."}
 if($enterpriseAcl.AreAccessRulesProtected){throw "Provisioner must not protect the inherited EnterpriseIT DACL."}
 Assert-DataAcl -Path $p.PostgreSql -Leaf:$false
 Assert-DataAcl -Path $p.Version -Leaf:$false
 Assert-DataAcl -Path $p.Data -Leaf:$true
 # EnterpriseIT is created with a NULL descriptor by the same elevated identity
 # that built the fixture, so its owner must match the fixture ProgramData
 # owner: the provisioner must neither take ownership nor set a fixed owner.
 $pdOwner=(Get-Acl -LiteralPath $t.ProgramData).GetOwner([Security.Principal.SecurityIdentifier])
 $enterpriseOwner=$enterpriseAcl.GetOwner([Security.Principal.SecurityIdentifier])
 if(-not $pdOwner.Equals($enterpriseOwner)){throw "Provisioner rewrote EnterpriseIT ownership ($enterpriseOwner vs fixture $pdOwner)."}
 # 2. Verify-only succeeds and a second provision is idempotent (file IDs and
 #    ACL SDDL unchanged).
 $dataId=[EnterpriseIT.ProvisionFileId]::Get($p.Data)
 $dataSddl=(Get-Acl -LiteralPath $p.Data).Sddl
 $r=Invoke-Provisioner @('--verify-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -ne 0 -or $r.StdOut.Trim() -ne 'OK'){throw "Verify failed: $($r.ExitCode) $($r.StdErr)"}
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -ne 0 -or $r.StdOut.Trim() -ne 'OK'){throw "Idempotent provision failed: $($r.ExitCode) $($r.StdErr)"}
 if([EnterpriseIT.ProvisionFileId]::Get($p.Data) -ne $dataId){throw "Idempotent rerun replaced the data directory identity."}
 if((Get-Acl -LiteralPath $p.Data).Sddl -cne $dataSddl){throw "Idempotent rerun rewrote the data directory ACL."}
 Assert-DataAcl -Path $p.Data -Leaf:$true
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 3. Verify-only on a missing store fails closed.
$t=New-TestRoot "verify-missing"
try{
 $r=Invoke-Provisioner @('--verify-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -eq 0){throw "Verify-only must fail for a missing store"}
 if($r.StdErr -notmatch 'missing-required-object'){throw "Unexpected verify error: $($r.StdErr)"}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 4. Invalid arguments, non-service SIDs and duplicate SIDs are rejected with
#    exit code 2 before any object is touched.
$t=New-TestRoot "badargs"
try{
 foreach($badArgs in @(
  @('--provision-data'),
  @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid),
  @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','../18'),
  @('--provision-data','--bootstrap-sid','S-1-5-21-1-2-3-1000','--postgres-sid',$postgresSid,'--pg-version','18'),
  @('--verify-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$bootstrapSid,'--pg-version','18')
 )){
  $fullArgs=@($badArgs)+@('--program-data-root',$t.ProgramData)
  $r=Invoke-Provisioner $fullArgs
  if($r.ExitCode -ne 2){throw "Invalid arguments must exit 2 (got $($r.ExitCode)): $($badArgs -join ' ')"}
 }
 if(Test-Path -LiteralPath (Join-Path $t.ProgramData "EnterpriseIT")){throw "Invalid-argument rejection must not create EnterpriseIT."}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 5. Existing wrong ACL (extra ACE on the data leaf) fails closed without
#    mutating the leaf or its ancestors.
$t=New-TestRoot "wrongacl"
try{
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -ne 0){throw "Setup provision failed: $($r.StdErr)"}
 $p=Get-DataPaths $t.ProgramData
 $acl=Get-Acl -LiteralPath $p.Data
 $acl.SetAccessRuleProtection($true,$false)
 $rule=New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Users","Modify","Allow")
 $acl.AddAccessRule($rule)
 Set-Acl -LiteralPath $p.Data -AclObject $acl
 $beforeSddl=(Get-Acl -LiteralPath $p.Data).Sddl
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -eq 0){throw "Provisioner must fail closed on an extra ACE."}
 if($r.StdErr -notmatch 'acl-dacl-mismatch'){throw "Unexpected wrong-ACL error: $($r.StdErr)"}
 if((Get-Acl -LiteralPath $p.Data).Sddl -cne $beforeSddl){throw "Failed provisioning mutated the rejected data leaf."}
 $userAce=@((Get-Acl -LiteralPath $p.Data).Access|Where-Object{$_.IdentityReference.Value -ieq 'BUILTIN\Users'})
 if($userAce.Count -lt 1){throw "Injected Users ACE must remain after the failed run."}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 6. A junction at the PostgreSQL component is rejected by handle before any
#    child is created, and the junction target is never mutated.
$t=New-TestRoot "reparse-postgresql"
try{
 $p=Get-DataPaths $t.ProgramData
 [IO.Directory]::CreateDirectory($p.Enterprise)|Out-Null
 $target=Join-Path $t.Root "pg-target"
 [IO.Directory]::CreateDirectory($target)|Out-Null
 $cmd=& cmd.exe /c "mklink /J `"$($p.PostgreSql)`" `"$target`""
 if($LASTEXITCODE -ne 0){throw "Could not create junction fixture: $cmd"}
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -eq 0){throw "Junction PostgreSQL component must be rejected."}
 if($r.StdErr -notmatch 'unexpected-object-type:postgresql-root'){throw "Unexpected junction error: $($r.StdErr)"}
 if(Test-Path -LiteralPath (Join-Path $target "data")){throw "Junction rejection must not create children in the target."}
 if(-not((Get-Item -LiteralPath $p.PostgreSql -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Rejected junction must be left in place."}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 7. An ordinary intermediate ancestor reached through a junction is rejected
#    before EnterpriseIT creation (ancestor reparse TOCTOU guard).
$t=New-TestRoot "ancestor-junction"
try{
 $ordinary=Join-Path $t.ProgramData 'nested'
 [IO.Directory]::CreateDirectory($ordinary)|Out-Null
 $link=Join-Path $t.Root 'intermediate-link'
 & cmd.exe /c "mklink /J `"$link`" `"$($t.ProgramData)`"" | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not create ancestor junction fixture.'}
 $throughLink=Join-Path $link 'nested'
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$throughLink)
 if($r.ExitCode -eq 0 -or $r.StdErr -notmatch 'unexpected-object-type:programdata-ancestor'){
  throw "Intermediate junction must be rejected by handle: $($r.StdErr)"
 }
 if(Test-Path -LiteralPath (Join-Path $ordinary 'EnterpriseIT')){throw 'Ancestor junction rejection mutated its target.'}
 Remove-Item -LiteralPath $link -Force -ErrorAction Stop
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 8. A broad-write ProgramData ancestor is untrusted; rejection happens before
#    any child creation.
$t=New-TestRoot "ancestor-broad-write"
try{
 $rootAcl=Get-Acl -LiteralPath $t.Root
 $everyone=[Security.Principal.SecurityIdentifier]::new('S-1-1-0')
 $broadWrite=[Security.AccessControl.FileSystemAccessRule]::new(
  $everyone,
  [Security.AccessControl.FileSystemRights]::Modify,
  [Security.AccessControl.InheritanceFlags]::ContainerInherit,
  [Security.AccessControl.PropagationFlags]::None,
  [Security.AccessControl.AccessControlType]::Allow)
 $rootAcl.SetAccessRuleProtection($true,$false)
 $rootAcl.AddAccessRule($broadWrite)
 Set-Acl -LiteralPath $t.Root -AclObject $rootAcl
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -eq 0 -or $r.StdErr -notmatch 'programdata-acl-unsafe'){throw "Broad-write ancestor must be rejected: $($r.StdErr)"}
 if(Test-Path -LiteralPath (Join-Path $t.ProgramData 'EnterpriseIT')){throw 'Untrusted ancestor rejection must happen before child creation.'}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 9. A regular file occupying the versioned directory slot is rejected without
#    touching the file.
$t=New-TestRoot "file-at-version"
try{
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -ne 0){throw "Setup provision failed: $($r.StdErr)"}
 $p=Get-DataPaths $t.ProgramData
 Remove-Item -LiteralPath $p.Version -Recurse -Force
 [IO.File]::WriteAllText($p.Version,'sentinel-version-slot')
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
 if($r.ExitCode -eq 0){throw "A file in the versioned directory slot must be rejected."}
 if([IO.File]::ReadAllText($p.Version) -cne 'sentinel-version-slot'){throw "Rejected file was mutated by the provisioner."}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 10. Test-only fault injection lives in a separate executable outside the
#     source tree; the release executable must ignore the environment key.
if(-not($env:RUNNER_TEMP)){throw 'CI runner temporary directory is required for the fault fixture build.'}
$buildId=[guid]::NewGuid().ToString('N')
$buildRoot=Join-Path $env:RUNNER_TEMP ('pg-fault-build-' + $buildId)
$outDir=Join-Path $buildRoot 'out'
$fixtureSource=Join-Path $buildRoot 'source'
$fixtureProject=Join-Path $fixtureSource 'EnterpriseIT.PostgreSQLBootstrap.csproj'
$faultExe=Join-Path $outDir 'EnterpriseIT.PostgreSQLBootstrap.exe'
[IO.Directory]::CreateDirectory($fixtureSource)|Out-Null
Copy-Item -LiteralPath $project -Destination $fixtureProject
foreach($source in Get-ChildItem -LiteralPath $projectDir -Filter '*.cs' -File){
 Copy-Item -LiteralPath $source.FullName -Destination $fixtureSource
}
& dotnet build $fixtureProject --configuration Release --output $outDir '-p:DefineConstants=POSTGRES_TEST_FAULTS'
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $faultExe -PathType Leaf)){
 throw 'Could not build isolated PostgreSQL fault fixture executable.'
}
$t=New-TestRoot "release-no-test-hook"
try{
 $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData) -Fault 'after-final-verification'
 if($r.ExitCode -ne 0 -or $r.StdOut.Trim() -ne 'OK'){throw 'Release executable unexpectedly enabled the test-only fault hook.'}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

foreach($stage in @('after-create-postgresql','after-create-version','after-create-data','after-final-verification')){
 # Fresh store: the fault must roll back every directory this invocation can
 # prove it created, while EnterpriseIT is deliberately retained.
 $t=New-TestRoot ('fault-fresh-' + $stage)
 try{
  $p=Get-DataPaths $t.ProgramData
  $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData) -Executable $faultExe -Fault $stage
  if($r.ExitCode -eq 0 -or $r.StdErr.Trim() -ne 'test-injected-fault'){throw "Fresh fault did not reach stage $stage: $($r.ExitCode) $($r.StdErr)"}
  if(Test-Path -LiteralPath $p.PostgreSql){throw "Fresh fault left PostgreSQL behind after proven-safe rollback: $stage"}
  if(Test-Path -LiteralPath $p.Data){throw "Fresh fault left the data leaf behind: $stage"}
  if(-not(Test-Path -LiteralPath $p.Enterprise -PathType Container)){throw 'Rollback unexpectedly removed EnterpriseIT.'}
 }finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

 # Fully pre-existing store: a failed retry never removes or rewrites it.
 $t=New-TestRoot ('fault-existing-' + $stage)
 try{
  $p=Get-DataPaths $t.ProgramData
  $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData)
  if($r.ExitCode -ne 0){throw 'Existing-store fault fixture setup failed.'}
  $dataId=[EnterpriseIT.ProvisionFileId]::Get($p.Data)
  $dataSddl=(Get-Acl -LiteralPath $p.Data).Sddl
  $r=Invoke-Provisioner @('--provision-data','--bootstrap-sid',$bootstrapSid,'--postgres-sid',$postgresSid,'--pg-version','18','--program-data-root',$t.ProgramData) -Executable $faultExe -Fault $stage
  if($r.ExitCode -eq 0 -or $r.StdErr.Trim() -ne 'test-injected-fault'){throw "Existing fault did not reach stage $stage: $($r.ExitCode) $($r.StdErr)"}
  if(-not(Test-Path -LiteralPath $p.Data -PathType Container)){throw 'Fault removed an existing data leaf.'}
  if([EnterpriseIT.ProvisionFileId]::Get($p.Data) -ne $dataId){throw 'Fault replaced an existing data leaf identity.'}
  if((Get-Acl -LiteralPath $p.Data).Sddl -cne $dataSddl){throw 'Fault rewrote an existing data leaf ACL.'}
  Assert-DataAcl -Path $p.Data -Leaf:$true
 }finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}
}

Write-Host "PostgreSQL data-directory native provisioning tests passed."
