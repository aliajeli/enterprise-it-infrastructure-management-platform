param([Parameter(Mandatory=$true)][string]$FaultHelperPath)
$ErrorActionPreference="Stop"
# Credential Vault provisioner policy/integration tests.
# Run as LocalSystem in an isolated CI fixture so exact ACLs can be independently
# inspected and adversarial fixtures created without changing production ACLs.
# A separate elevated-admin smoke test verifies the actual provisioning entry point.

$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$helperProject=Join-Path $repoRoot "apps\api\windows\keyring-storage-helper\CredentialVault.KeyringStorageHelper.csproj"
$helperDll=Join-Path $repoRoot "apps\api\windows\keyring-storage-helper\bin\Release\net10.0-windows\CredentialVault.KeyringStorageHelper.dll"
$helperExe=Join-Path $repoRoot "apps\api\windows\keyring-storage-helper\bin\Release\net10.0-windows\CredentialVault.KeyringStorageHelper.exe"
if(-not(Test-Path -LiteralPath $helperDll -PathType Leaf) -and -not(Test-Path -LiteralPath $helperExe -PathType Leaf)){
 dotnet build $helperProject --configuration Release | Out-Host
 if($LASTEXITCODE -ne 0){throw "Could not build keyring storage helper for Vault provisioning tests."}
}
$helperPath=if(Test-Path -LiteralPath $helperExe -PathType Leaf){$helperExe}else{$helperDll}
function Invoke-Provisioner([string[]]$Arguments,[string]$Executable=$helperPath,[string]$Fault=''){
 $start=[Diagnostics.ProcessStartInfo]::new()
 if($Executable.EndsWith(".dll",[StringComparison]::OrdinalIgnoreCase)){$start.FileName="dotnet";$start.ArgumentList.Add($Executable)}else{$start.FileName=$Executable}
 foreach($a in $Arguments){$start.ArgumentList.Add([string]$a)}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $null=$start.Environment.Remove('ENTERPRISEIT_VAULT_TEST_FAULT')
 if($Fault){$start.Environment['ENTERPRISEIT_VAULT_TEST_FAULT']=$Fault}
 $p=[Diagnostics.Process]::Start($start)
 try{
  $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(30000)){try{$p.Kill($true);$p.WaitForExit()}catch{};throw 'Vault fixture helper timed out.'}
  [pscustomobject]@{ExitCode=$p.ExitCode;StdOut=$outTask.GetAwaiter().GetResult();StdErr=$errTask.GetAwaiter().GetResult()}
 }finally{$p.Dispose()}
}

$sidOutput=(& sc.exe showsid EnterpriseITApi 2>&1|Out-String)
if($LASTEXITCODE -ne 0){throw "Could not resolve API service SID for test."}
$sidMatch=[regex]::Match($sidOutput,'S-1-5-80-(?:\d+-){4}\d+')
if(-not $sidMatch.Success){throw "SCM returned an invalid API service SID for test."}
$serviceSid=$sidMatch.Value
$badSid="S-1-5-21-1-2-3-1000"

function New-TestRoot([string]$Name){
 $root=Join-Path $env:TEMP ("enterpriseit-vault-provision-" + $Name + "-" + [guid]::NewGuid().ToString("N"))
 $pd=Join-Path $root "ProgramData"
 [IO.Directory]::CreateDirectory($pd)|Out-Null
 # Explicit protected fixture baseline; do not depend on the machine TEMP ACL.
 $acl=[Security.AccessControl.DirectorySecurity]::new()
 $acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @('S-1-5-18','S-1-5-32-544')){
  $identity=[Security.Principal.SecurityIdentifier]::new($sid)
  $rule=[Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
  $acl.AddAccessRule($rule)
 }
 Set-Acl -LiteralPath $pd -AclObject $acl
 return [pscustomobject]@{Root=$root;ProgramData=$pd}
}

function Get-VaultPaths([string]$ProgramData){
 $enterprise=Join-Path $ProgramData "EnterpriseIT"
 $vault=Join-Path $enterprise "CredentialVault"
 $lock=Join-Path $vault "keyring.lock"
 [pscustomobject]@{Enterprise=$enterprise;Vault=$vault;Lock=$lock}
}

function Assert-AclExact([string]$Path,[string]$ExpectedServiceSid){
 $item=Get-Item -LiteralPath $Path -Force
 $acl=Get-Acl -LiteralPath $Path
 $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
 if($owner -ne $ExpectedServiceSid){
  $kind=if($owner -eq 'S-1-5-18'){'system'}elseif($owner -eq 'S-1-5-32-544'){'administrators'}else{'other'}
  throw "Vault owner SID does not match the expected service SID (observed category: $kind)."
 }
 if($acl.AreAccessRulesProtected -ne $true){throw "DACL not protected for $Path"}
 $rules=@($acl.Access|Where-Object{-not $_.IsInherited})
 if($rules.Count -ne 2){throw "Expected exactly 2 explicit ACEs for $Path, got $($rules.Count)"}
 $expected=@(
  [pscustomobject]@{Identity=$ExpectedServiceSid;Rights=[System.Security.AccessControl.FileSystemRights]::FullControl},
  [pscustomobject]@{Identity="NT AUTHORITY\SYSTEM";Rights=[System.Security.AccessControl.FileSystemRights]::FullControl}
 )
 foreach($e in $expected){
  $wanted=try{([Security.Principal.NTAccount]::new($e.Identity)).Translate([Security.Principal.SecurityIdentifier]).Value}catch{$e.Identity}
  $match=@($rules|Where-Object{
   $actual=try{$_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value}catch{$_.IdentityReference.Value}
   $actual -eq $wanted -and $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and ($_.FileSystemRights -band $e.Rights) -eq $e.Rights
  })
  if($match.Count -ne 1){throw "Missing expected Vault ACE."}
 }
}

# 1. Fresh create
$t=New-TestRoot "fresh"
try{
 $r=Invoke-Provisioner @("--provision-vault","--service-sid",$serviceSid,"--program-data-root",$t.ProgramData)
 if($r.ExitCode -ne 0 -or $r.StdOut.Trim() -ne "OK"){throw "Fresh provision failed: exit=$($r.ExitCode) stderr=$($r.StdErr) stdout=$($r.StdOut)"}
 $p=Get-VaultPaths $t.ProgramData
 foreach($path in @($p.Enterprise,$p.Vault,$p.Lock)){if(-not(Test-Path -LiteralPath $path)){throw "Missing provisioned path: $path"}}
 Assert-AclExact -Path $p.Vault -ExpectedServiceSid $serviceSid
 Assert-AclExact -Path $p.Lock -ExpectedServiceSid $serviceSid
 $vaultItem=Get-Item -LiteralPath $p.Vault -Force
 $lockItem=Get-Item -LiteralPath $p.Lock -Force
 if(($vaultItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Vault is reparse point"}
 if(($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Lock is reparse point"}
 if($lockItem.PSIsContainer){throw "Lock must be file"}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 2. Idempotent rerun preserves identity
$t=New-TestRoot "idempotent"
try{
 $r1=Invoke-Provisioner @("--provision-vault","--service-sid",$serviceSid,"--program-data-root",$t.ProgramData)
 if($r1.ExitCode -ne 0){throw "First provision failed: $($r1.StdErr)"}
 $p=Get-VaultPaths $t.ProgramData
 $vaultId=(Get-Item -LiteralPath $p.Vault -Force).CreationTimeUtc.Ticks.ToString() + ":" + (Get-Acl -LiteralPath $p.Vault).Sddl
 $lockLen=(Get-Item -LiteralPath $p.Lock -Force).Length
 $r2=Invoke-Provisioner @("--provision-vault","--service-sid",$serviceSid,"--program-data-root",$t.ProgramData)
 if($r2.ExitCode -ne 0 -or $r2.StdOut.Trim() -ne "OK"){throw "Second provision not idempotent: $($r2.ExitCode) $($r2.StdErr)"}
 $vaultId2=(Get-Item -LiteralPath $p.Vault -Force).CreationTimeUtc.Ticks.ToString() + ":" + (Get-Acl -LiteralPath $p.Vault).Sddl
 if($vaultId -ne $vaultId2){throw "Vault identity/SDDL changed on idempotent rerun"}
 if((Get-Item -LiteralPath $p.Lock -Force).Length -ne $lockLen){throw "Lock changed on idempotent rerun"}
 Assert-AclExact -Path $p.Vault -ExpectedServiceSid $serviceSid
 Assert-AclExact -Path $p.Lock -ExpectedServiceSid $serviceSid
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 3. Verify-only on missing store fails closed
$t=New-TestRoot "verify-missing"
try{
 $r=Invoke-Provisioner @("--verify-vault","--service-sid",$serviceSid,"--program-data-root",$t.ProgramData)
 if($r.ExitCode -eq 0){throw "Verify-only must fail for missing store"}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 4. Invalid/non-service SID rejected
$t=New-TestRoot "badsid"
try{
 $r=Invoke-Provisioner @("--provision-vault","--service-sid",$badSid,"--program-data-root",$t.ProgramData)
 if($r.ExitCode -eq 0){throw "Non-service SID must be rejected"}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 5. Existing wrong ACL (extra ACE) fails closed without mutation
$t=New-TestRoot "wrongacl"
try{
 $r1=Invoke-Provisioner @("--provision-vault","--service-sid",$serviceSid,"--program-data-root",$t.ProgramData)
 if($r1.ExitCode -ne 0){throw "Setup provision failed: $($r1.StdErr)"}
 $p=Get-VaultPaths $t.ProgramData
 $acl=Get-Acl -LiteralPath $p.Lock
 $acl.SetAccessRuleProtection($true,$false)
 $rule=New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators","FullControl","Allow")
 $acl.AddAccessRule($rule)
 Set-Acl -LiteralPath $p.Lock -AclObject $acl
 $r2=Invoke-Provisioner @("--provision-vault","--service-sid",$serviceSid,"--program-data-root",$t.ProgramData)
 if($r2.ExitCode -eq 0){throw "Provisioner must fail closed on extra ACE"}
 $acl2=Get-Acl -LiteralPath $p.Lock
 $adminAce=@($acl2.Access|Where-Object{$_.IdentityReference.Value -ieq "BUILTIN\Administrators" -and -not $_.IsInherited})
 if($adminAce.Count -lt 1){throw "Provisioner mutated unexpected object (admin ACE removed) - should have left it unchanged and failed"}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 6. Reparse point at Vault directory rejected
$t=New-TestRoot "reparse-vault"
try{
 $enterprise=Join-Path $t.ProgramData "EnterpriseIT"
 [IO.Directory]::CreateDirectory($enterprise)|Out-Null
 $target=Join-Path $t.Root "vault-target"
 [IO.Directory]::CreateDirectory($target)|Out-Null
 $vault=Join-Path $enterprise "CredentialVault"
 $cmd=& cmd.exe /c "mklink /J `"$vault`" `"$target`""
 if($LASTEXITCODE -ne 0){throw "Could not create junction fixture: $cmd"}
 $r=Invoke-Provisioner @("--provision-vault","--service-sid",$serviceSid,"--program-data-root",$t.ProgramData)
 if($r.ExitCode -eq 0){throw "Junction Vault must be rejected"}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# An intermediate ProgramData ancestor junction must be rejected, even when
# the final directory itself is ordinary and on the same volume.
$t=New-TestRoot "ancestor-junction"
try{
 $ordinary=Join-Path $t.ProgramData 'nested'
 New-Item -ItemType Directory -Path $ordinary -Force|Out-Null
 $link=Join-Path $t.Root 'intermediate-link'
 & cmd.exe /c "mklink /J `"$link`" `"$($t.ProgramData)`"" | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Could not create ancestor junction fixture.'}
 $throughLink=Join-Path $link 'nested'
 $r=Invoke-Provisioner @('--provision-vault','--service-sid',$serviceSid,'--program-data-root',$throughLink)
 if($r.ExitCode -eq 0 -or $r.StdErr -notmatch 'unexpected-object-type:programdata-ancestor'){
  throw "Intermediate junction must be rejected by handle: $($r.StdErr)"
 }
 if(Test-Path -LiteralPath (Join-Path $ordinary 'EnterpriseIT')){throw 'Ancestor junction rejection mutated its target.'}
 Remove-Item -LiteralPath $link -Force -ErrorAction Stop
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 7. Lock file as directory rejected
$t=New-TestRoot "lock-dir"
try{
 $p=Get-VaultPaths $t.ProgramData
 [IO.Directory]::CreateDirectory($p.Vault)|Out-Null
 [IO.Directory]::CreateDirectory($p.Lock)|Out-Null
 $r=Invoke-Provisioner @("--provision-vault","--service-sid",$serviceSid,"--program-data-root",$t.ProgramData)
 if($r.ExitCode -eq 0){throw "Lock directory collision must be rejected"}
 if(-not(Test-Path -LiteralPath $p.Lock -PathType Container)){throw "Provisioner must not replace unexpected lock object"}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}

# 8. Invalid args rejected
$r=Invoke-Provisioner @("--provision-vault")
if($r.ExitCode -eq 0){throw "Missing --service-sid must be rejected"}
$r=Invoke-Provisioner @("--verify-vault","--service-sid","not-a-sid","--program-data-root",$env:TEMP)
if($r.ExitCode -eq 0){throw "Invalid SID must be rejected"}

# 9. Orchestrator WhatIf should not invoke helper (policy check in script)
$orch=Get-Content -LiteralPath (Join-Path $repoRoot "scripts\windows\orchestrate-windows-services.ps1") -Raw
if($orch -notmatch 'if\(\$WhatIfPreference\)\{\$plan\|ConvertTo-Json -Depth 5;return\}'){throw "Orchestrator must return plan on WhatIf without invoking provisioner"}
if($orch -notmatch 'Invoke-CredentialVaultProvisioner'){throw "Orchestrator must call Vault provisioner"}
if($orch -notmatch 'VerifyOnly'){throw "Orchestrator must perform verify-only before API start"}

# Test-only fault injection is compiled into a separate executable outside the
# source tree. The normal release executable must ignore this environment key.
if(-not(Test-Path -LiteralPath $FaultHelperPath -PathType Leaf)){throw 'Fault-only Vault fixture executable is missing.'}
$t=New-TestRoot 'release-no-test-hook'
try{
 $args=@('--provision-vault','--service-sid',$serviceSid,'--program-data-root',$t.ProgramData)
 $r=Invoke-Provisioner -Arguments $args -Fault 'after-final-verification'
 if($r.ExitCode -ne 0 -or $r.StdOut.Trim() -ne 'OK'){throw 'Release helper unexpectedly enabled the test-only fault hook.'}
}finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}
foreach($stage in @('after-vault-identity','after-lock-identity','after-final-verification')){
 # Newly created vault and lock are removed, but EnterpriseIT is deliberately
 # retained; do not recursively delete production ancestors during rollback.
 $t=New-TestRoot ('fault-fresh-'+$stage)
 try{
  $p=Get-VaultPaths $t.ProgramData
  $args=@('--provision-vault','--service-sid',$serviceSid,'--program-data-root',$t.ProgramData)
  $r=Invoke-Provisioner -Arguments $args -Executable $FaultHelperPath -Fault $stage
  if($r.ExitCode -eq 0 -or $r.StdErr.Trim() -ne 'test-injected-fault'){throw "Fresh fault did not reach the intended injection stage: $stage"}
  if(Test-Path -LiteralPath $p.Vault){throw "Fresh fault left a Vault after proven-safe rollback: $stage"}
  if(-not(Test-Path -LiteralPath $p.Enterprise -PathType Container)){throw 'Rollback unexpectedly removed EnterpriseIT.'}
 }finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}
 # A fully pre-existing store is never removed or rewritten by a failed retry.
 $t=New-TestRoot ('fault-existing-'+$stage)
 try{
  $p=Get-VaultPaths $t.ProgramData
  $args=@('--provision-vault','--service-sid',$serviceSid,'--program-data-root',$t.ProgramData)
  $r=Invoke-Provisioner -Arguments $args
  if($r.ExitCode -ne 0){throw 'Existing-store fault fixture setup failed.'}
  [IO.File]::WriteAllText($p.Lock,'synthetic-sentinel')
  $vaultTime=(Get-Item -LiteralPath $p.Vault -Force).CreationTimeUtc.Ticks
  $lockTime=(Get-Item -LiteralPath $p.Lock -Force).CreationTimeUtc.Ticks
  $r=Invoke-Provisioner -Arguments $args -Executable $FaultHelperPath -Fault $stage
  if($r.ExitCode -eq 0 -or $r.StdErr.Trim() -ne 'test-injected-fault'){throw "Existing fault did not reach the intended injection stage: $stage"}
  if(-not(Test-Path -LiteralPath $p.Vault -PathType Container) -or -not(Test-Path -LiteralPath $p.Lock -PathType Leaf)){throw 'Fault removed an existing Vault object.'}
  if((Get-Item -LiteralPath $p.Vault -Force).CreationTimeUtc.Ticks -ne $vaultTime -or (Get-Item -LiteralPath $p.Lock -Force).CreationTimeUtc.Ticks -ne $lockTime -or [IO.File]::ReadAllText($p.Lock) -cne 'synthetic-sentinel'){throw 'Fault changed an existing Vault object.'}
  Assert-AclExact -Path $p.Vault -ExpectedServiceSid $serviceSid
  Assert-AclExact -Path $p.Lock -ExpectedServiceSid $serviceSid
 }finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}
}
# Failures before identity capture must leave unproven created objects in place.
# This is intentionally different from successful identity-checked rollback.
foreach($stage in @('before-vault-identity','before-lock-identity')){
 $t=New-TestRoot ('fault-unproven-'+$stage)
 try{
  $p=Get-VaultPaths $t.ProgramData
  $parameters=@('--provision-vault','--service-sid',$serviceSid,'--program-data-root',$t.ProgramData)
  $r=Invoke-Provisioner -Arguments $parameters -Executable $FaultHelperPath -Fault $stage
  if($r.ExitCode -eq 0 -or $r.StdErr.Trim() -ne 'test-injected-fault'){throw "Unproven-identity fault was not reached: $stage"}
  if(-not(Test-Path -LiteralPath $p.Vault -PathType Container)){throw 'Rollback removed an object without a captured Vault identity.'}
  Assert-AclExact -Path $p.Vault -ExpectedServiceSid $serviceSid
  if($stage -eq 'before-lock-identity'){
   if(-not(Test-Path -LiteralPath $p.Lock -PathType Leaf)){throw 'Rollback removed a lock without a captured identity.'}
   Assert-AclExact -Path $p.Lock -ExpectedServiceSid $serviceSid
  }elseif(Test-Path -LiteralPath $p.Lock){throw 'Unexpected lock before lock creation.'}
 }finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}
 # Existing objects are also never deleted when identity capture is interrupted.
 $t=New-TestRoot ('fault-unproven-existing-'+$stage)
 try{
  $p=Get-VaultPaths $t.ProgramData
  $parameters=@('--provision-vault','--service-sid',$serviceSid,'--program-data-root',$t.ProgramData)
  $r=Invoke-Provisioner -Arguments $parameters
  if($r.ExitCode -ne 0){throw 'Existing-store identity fixture setup failed.'}
  [IO.File]::WriteAllText($p.Lock,'synthetic-sentinel')
  $r=Invoke-Provisioner -Arguments $parameters -Executable $FaultHelperPath -Fault $stage
  if($r.ExitCode -eq 0 -or $r.StdErr.Trim() -ne 'test-injected-fault'){throw "Existing identity fault was not reached: $stage"}
  if(-not(Test-Path -LiteralPath $p.Lock -PathType Leaf) -or [IO.File]::ReadAllText($p.Lock) -cne 'synthetic-sentinel'){throw 'Fault changed an existing lock.'}
  Assert-AclExact -Path $p.Vault -ExpectedServiceSid $serviceSid
  Assert-AclExact -Path $p.Lock -ExpectedServiceSid $serviceSid
 }finally{Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue}
}
# Two independent provisioners race on the same fresh fixture. At least one
# must succeed; failures must not corrupt the winning store, and a verified
# retry must preserve a sentinel. Scheduling is nondeterministic, so this is
# supplemental coverage rather than proof against all races.
for($round=0;$round -lt 3;$round++){
 $t=New-TestRoot ('concurrent-'+$round)
 $processes=[Collections.Generic.List[object]]::new()
 try{
  $p=Get-VaultPaths $t.ProgramData
  foreach($index in 1..2){
   $start=[Diagnostics.ProcessStartInfo]::new()
   if($helperPath.EndsWith('.dll',[StringComparison]::OrdinalIgnoreCase)){$start.FileName='dotnet';$start.ArgumentList.Add($helperPath)}else{$start.FileName=$helperPath}
   foreach($arg in @('--provision-vault','--service-sid',$serviceSid,'--program-data-root',$t.ProgramData)){$start.ArgumentList.Add($arg)}
   $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
   $null=$start.Environment.Remove('ENTERPRISEIT_VAULT_TEST_FAULT')
   $process=[Diagnostics.Process]::Start($start)
   $processes.Add([pscustomobject]@{Process=$process;Out=$process.StandardOutput.ReadToEndAsync();Err=$process.StandardError.ReadToEndAsync()})
  }
  $successes=0
  foreach($entry in $processes){
   if(-not $entry.Process.WaitForExit(30000)){throw 'Concurrent Vault provisioner timed out.'}
   $output=$entry.Out.GetAwaiter().GetResult();$null=$entry.Err.GetAwaiter().GetResult()
   if($entry.Process.ExitCode -eq 0){
    if($output.Trim() -cne 'OK'){throw 'Concurrent Vault success response was invalid.'}
    $successes++
   }
  }
  if($successes -lt 1){throw 'Neither concurrent Vault provisioner succeeded.'}
  Assert-AclExact -Path $p.Vault -ExpectedServiceSid $serviceSid
  Assert-AclExact -Path $p.Lock -ExpectedServiceSid $serviceSid
  [IO.File]::WriteAllText($p.Lock,'race-synthetic-sentinel')
  $retry=Invoke-Provisioner -Arguments @('--provision-vault','--service-sid',$serviceSid,'--program-data-root',$t.ProgramData)
  if($retry.ExitCode -ne 0 -or [IO.File]::ReadAllText($p.Lock) -cne 'race-synthetic-sentinel'){throw 'Concurrent Vault store was not stable on retry.'}
  Assert-AclExact -Path $p.Vault -ExpectedServiceSid $serviceSid
  Assert-AclExact -Path $p.Lock -ExpectedServiceSid $serviceSid
 }finally{
  foreach($entry in $processes){
   try{if(-not $entry.Process.HasExited){$entry.Process.Kill($true);$entry.Process.WaitForExit()}}catch{}
   $entry.Process.Dispose()
  }
  Remove-Item -LiteralPath $t.Root -Recurse -Force -ErrorAction SilentlyContinue
 }
}
Write-Host "Credential Vault provisioning and isolated fault and concurrent rollback tests passed."
