$ErrorActionPreference="Stop"
# Credential Vault provisioner policy/integration tests.
# Runs on Windows CI as admin. Resolve the actual service SID via SCM for ACL shape tests.

$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$helperProject=Join-Path $repoRoot "apps\api\windows\keyring-storage-helper\CredentialVault.KeyringStorageHelper.csproj"
$helperDll=Join-Path $repoRoot "apps\api\windows\keyring-storage-helper\bin\Release\net10.0-windows\CredentialVault.KeyringStorageHelper.dll"
$helperExe=Join-Path $repoRoot "apps\api\windows\keyring-storage-helper\bin\Release\net10.0-windows\CredentialVault.KeyringStorageHelper.exe"
if(-not(Test-Path -LiteralPath $helperDll -PathType Leaf) -and -not(Test-Path -LiteralPath $helperExe -PathType Leaf)){
 dotnet build $helperProject --configuration Release | Out-Host
 if($LASTEXITCODE -ne 0){throw "Could not build keyring storage helper for Vault provisioning tests."}
}
$helperPath=if(Test-Path -LiteralPath $helperExe -PathType Leaf){$helperExe}else{$helperDll}
function Invoke-Provisioner([string[]]$Arguments){
 $start=[Diagnostics.ProcessStartInfo]::new()
 if($helperPath.EndsWith(".dll",[StringComparison]::OrdinalIgnoreCase)){$start.FileName="dotnet";$start.ArgumentList.Add($helperPath)}else{$start.FileName=$helperPath}
 foreach($a in $Arguments){$start.ArgumentList.Add([string]$a)}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $p=[Diagnostics.Process]::Start($start)
 $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync();$p.WaitForExit()
 [pscustomobject]@{ExitCode=$p.ExitCode;StdOut=$outTask.GetAwaiter().GetResult();StdErr=$errTask.GetAwaiter().GetResult()}
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
 # ProgramData in test root is a normal directory; provisioner validates it is not reparse and
 # has no broad write ACEs. We do not copy OS ProgramData ACLs into the test root.
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
 if($acl.Owner -ne $ExpectedServiceSid){throw "Owner mismatch for ${Path}: $($acl.Owner)"}
 if($acl.AreAccessRulesProtected -ne $true){throw "DACL not protected for $Path"}
 $rules=@($acl.Access|Where-Object{-not $_.IsInherited})
 if($rules.Count -ne 2){throw "Expected exactly 2 explicit ACEs for $Path, got $($rules.Count)"}
 $expected=@(
  [pscustomobject]@{Identity=$ExpectedServiceSid;Rights=[System.Security.AccessControl.FileSystemRights]::FullControl},
  [pscustomobject]@{Identity="NT AUTHORITY\SYSTEM";Rights=[System.Security.AccessControl.FileSystemRights]::FullControl}
 )
 foreach($e in $expected){
  $match=@($rules|Where-Object{$_.IdentityReference.Value -ieq $e.Identity -and $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and ($_.FileSystemRights -band $e.Rights) -eq $e.Rights})
  if($match.Count -ne 1){throw "Missing expected ACE $($e.Identity) on $Path"}
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

Write-Host "Credential Vault provisioning tests passed."
