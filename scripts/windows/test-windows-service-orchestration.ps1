$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "orchestrate-windows-services.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -ApiDatabaseUrl (ConvertTo-SecureString "unused" -AsPlainText -Force) -WorkerDatabaseUrl (ConvertTo-SecureString "unused" -AsPlainText -Force) -EdgeBindAddress "192.0.2.10" -EdgeHttpsPort 443 -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40)
$p=Get-WindowsServiceOrchestrationPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -EdgeBindAddress "192.0.2.10" -EdgeHttpsPort 443 -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40) -DataRoot (Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")
$expected=@("EnterpriseITPostgreSQL","EnterpriseITApi","EnterpriseITWorker","EnterpriseITWeb","EnterpriseITEdge")
if(($p.StartOrder -join ",") -ne ($expected -join ",")){throw "Five-service start order is incorrect."}
if($p.Dependencies.Count -ne 4 -or $p.ChangesFirewall -or $p.ChangesRouter -or $p.PortMapping){throw "Unsafe service orchestration policy."}
$bad=$false;try{Get-WindowsServiceOrchestrationPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -EdgeBindAddress "127.0.0.1" -EdgeHttpsPort 443 -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40) -DataRoot (Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")|Out-Null}catch{$bad=$true}
if(-not $bad){throw "Loopback Edge bind must be rejected."}
Write-Host "Five-service orchestration policy tests passed."
