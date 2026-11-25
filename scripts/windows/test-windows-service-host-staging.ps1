$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "stage-windows-service-hosts.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$p=Get-WindowsServiceHostStagePlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$expected=@("EnterpriseITApi","EnterpriseITWeb","EnterpriseITWorker","EnterpriseITEdge","EnterpriseITKeyringStorageHelper","EnterpriseITDpapiHelper","EnterpriseITPostgreSQLBootstrap")
if(($p.Services.Service -join ",") -ne ($expected -join ",") -or -not $p.SelfContained -or -not $p.PublishSingleFile -or $p.RuntimeIdentifier -ne "win-x64"){throw "Unexpected Windows service host stage plan."}
$rejected=$false;try{Get-WindowsServiceHostStagePlan -InstallRoot (Join-Path $pf "EnterpriseIT\current")|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Non-versioned host stage root was accepted."}
Write-Host "Windows service host stage policy tests passed."

foreach($item in $p.Services){
 if(-not(Test-Path -LiteralPath $item.Project -PathType Leaf)){throw "Service host project is missing from stage plan: $($item.Project)"}
 if([string]::IsNullOrWhiteSpace($item.Executable) -or -not $item.Executable.EndsWith(".exe",[StringComparison]::OrdinalIgnoreCase)){throw "Service host executable name is invalid."}
}
if(-not $p.Immutable){throw "Service host payload must be immutable."}
