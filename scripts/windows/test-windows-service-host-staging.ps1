$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "stage-windows-service-hosts.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$p=Get-WindowsServiceHostStagePlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3")
$expected=@("EnterpriseITApi","EnterpriseITWeb","EnterpriseITWorker","EnterpriseITEdge")
if(($p.Services.Service -join ",") -ne ($expected -join ",") -or -not $p.SelfContained -or -not $p.PublishSingleFile -or $p.RuntimeIdentifier -ne "win-x64"){throw "Unexpected Windows service host stage plan."}
$rejected=$false;try{Get-WindowsServiceHostStagePlan -InstallRoot (Join-Path $pf "EnterpriseIT\current")|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Non-versioned host stage root was accepted."}
Write-Host "Windows service host stage policy tests passed."
