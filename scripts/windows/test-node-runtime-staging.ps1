$ErrorActionPreference = "Stop"
$pf = [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "stage-node-runtime.ps1") -NodeRuntimeDirectory (Split-Path (Get-Command node.exe -ErrorAction Stop).Source -Parent) -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$nodePath = (Get-Command node.exe -ErrorAction Stop).Source
$version = (& $nodePath --version 2>&1 | Out-String).Trim()
$plan = Get-NodeRuntimeStagePlan -NodeRuntimeDirectory (Split-Path $nodePath -Parent) -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -NodeVersion $version
if ($plan.NodeMajorVersion -ne 26 -or $plan.NodeVersion -notmatch '^v26\.' -or -not $plan.Immutable -or -not $plan.CopyAllRuntimeFiles -or $plan.Destination -ne (Join-Path $pf "EnterpriseIT\1.2.3\runtime")) {
    throw "Unexpected Node runtime stage plan."
}
$rejected = $false
try { Get-NodeRuntimeStagePlan -NodeRuntimeDirectory (Split-Path $nodePath -Parent) -InstallRoot (Join-Path $pf "EnterpriseIT\current") -NodeVersion $version | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Non-versioned Node runtime stage root was accepted." }
$rejected = $false
try { Get-NodeRuntimeStagePlan -NodeRuntimeDirectory (Split-Path $nodePath -Parent) -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -NodeVersion "v25.9.0" | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Unsupported Node major version was accepted." }
Write-Host "Node runtime staging policy tests passed."
