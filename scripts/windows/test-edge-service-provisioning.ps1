$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "provision-edge-service.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -BindAddress "192.0.2.10" -HttpsPort 443 -TlsHostname "it.example.internal" -CertificateThumbprint ("A"*40)
$valid=Get-EdgeServiceProvisioningPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -BindAddress "192.0.2.10" -HttpsPort 443 -TlsHostname "it.example.internal" -CertificateThumbprint ("A"*40)
if($valid.ServiceName -ne "EnterpriseITEdge" -or $valid.ServiceAccount -ne "NT SERVICE\EnterpriseITEdge" -or $valid.StartService -or $valid.HttpsPort -ne 443){throw "Unexpected Edge service plan."}
$invalid=@(
 @{root=(Join-Path $pf "EnterpriseIT\current");ip="192.0.2.10";port=443;host="it.example.internal";thumb=("A"*40)},
 @{root=(Join-Path $pf "EnterpriseIT\1.2.3");ip="127.0.0.1";port=443;host="it.example.internal";thumb=("A"*40)},
 @{root=(Join-Path $pf "EnterpriseIT\1.2.3");ip="192.0.2.10";port=0;host="it.example.internal";thumb=("A"*40)},
 @{root=(Join-Path $pf "EnterpriseIT\1.2.3");ip="192.0.2.10";port=443;host="https://it.example.internal";thumb=("A"*40)},
 @{root=(Join-Path $pf "EnterpriseIT\1.2.3");ip="192.0.2.10";port=443;host="it.example.internal";thumb="bad"}
)
foreach($item in $invalid){$rejected=$false;try{Get-EdgeServiceProvisioningPlan -InstallRoot $item.root -BindAddress $item.ip -HttpsPort $item.port -TlsHostname $item.host -CertificateThumbprint $item.thumb|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Unsafe Edge service configuration was accepted."}}
$dry=[pscustomobject]@{ServiceName="EnterpriseITEdge";ServiceAccount="NT SERVICE\EnterpriseITEdge";InstallRoot=(Join-Path $pf "EnterpriseIT\1.2.3")}
$result=Invoke-EdgeServiceProvisioning -Plan $dry -WhatIf
if(-not $result.dryRun -or $result.serviceStarted){throw "Edge WhatIf must be side-effect free."}
Write-Host "Edge service provisioning policy tests passed."
