$ErrorActionPreference="Stop"
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "provision-edge-service.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -BindAddress "192.0.2.10" -HttpsPort 443 -TlsHostname "it.example.internal" -CertificateThumbprint ("A"*40)
$p=Get-EdgeServiceProvisioningPlan -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -BindAddress "192.0.2.10" -HttpsPort 443 -TlsHostname "it.example.internal" -CertificateThumbprint ("A"*40)
if($p.ServiceName -ne "EnterpriseITEdge" -or $p.ServiceAccount -ne "NT SERVICE\EnterpriseITEdge" -or $p.StartService -or $p.HttpsPort -ne 443){throw "Unexpected Edge service plan."}
$bad=@(@{root=(Join-Path $pf "EnterpriseIT\current");ip="192.0.2.10";port=443;host="it.example.internal";thumb=("A"*40)},@{root=(Join-Path $pf "EnterpriseIT\1.2.3");ip="127.0.0.1";port=443;host="it.example.internal";thumb=("A"*40)},@{root=(Join-Path $pf "EnterpriseIT\1.2.3");ip="192.0.2.10";port=0;host="it.example.internal";thumb=("A"*40)},@{root=(Join-Path $pf "EnterpriseIT\1.2.3");ip="192.0.2.10";port=443;host="https://it.example.internal";thumb=("A"*40)},@{root=(Join-Path $pf "EnterpriseIT\1.2.3");ip="192.0.2.10";port=443;host="it.example.internal";thumb="bad"})
$validFacts=[pscustomobject]@{HostPayloadExists=$true;LocalAddresses=@("192.0.2.10");PortOccupied=$false;CertificateFound=$true;HasPrivateKey=$true;Now=[DateTime]::UtcNow;NotBefore=([DateTime]::UtcNow.AddDays(-1));NotAfter=([DateTime]::UtcNow.AddDays(30));DnsName="it.example.internal";ServerAuthenticationEku=$true;ChainValid=$true;PrivateKeyProvider="RSA-CNG";PrivateKeyFileExists=$true}
$preflightResult=Test-EdgeServicePreflightFacts -Plan $p -Facts $validFacts
if(-not $preflightResult.valid){throw "Valid Edge certificate and listener facts should pass preflight."}
$invalidFacts=@(
 @{name="missing private key";change={param($f)$f.HasPrivateKey=$false}},
 @{name="hostname mismatch";change={param($f)$f.DnsName="other.example.internal"}},
 @{name="missing server auth";change={param($f)$f.ServerAuthenticationEku=$false}},
 @{name="untrusted chain";change={param($f)$f.ChainValid=$false}},
 @{name="unsupported key";change={param($f)$f.PrivateKeyProvider="ECDSA"}}
)
foreach($case in $invalidFacts){$facts=$validFacts|ConvertTo-Json -Depth 3|ConvertFrom-Json;& $case.change $facts;$rejected=$false;try{Test-EdgeServicePreflightFacts -Plan $p -Facts $facts|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Edge preflight accepted unsafe fact set: $($case.name)."}}
foreach($x in $bad){$rejected=$false;try{Get-EdgeServiceProvisioningPlan -InstallRoot $x.root -BindAddress $x.ip -HttpsPort $x.port -TlsHostname $x.host -CertificateThumbprint $x.thumb|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "Unsafe Edge config accepted."}}
$r=Invoke-EdgeServiceProvisioning -Plan ([pscustomobject]@{ServiceName="EnterpriseITEdge"}) -WhatIf
if(-not $r.dryRun -or $r.serviceStarted){throw "Edge WhatIf is not side-effect free."}
Write-Host "Edge provisioning policy tests passed."
