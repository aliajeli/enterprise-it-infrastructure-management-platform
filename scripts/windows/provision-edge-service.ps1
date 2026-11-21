[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
    [Parameter(Mandatory=$true)][string]$InstallRoot,
    [Parameter(Mandatory=$true)][string]$BindAddress,
    [int]$HttpsPort=443,
    [Parameter(Mandatory=$true)][string]$TlsHostname,
    [Parameter(Mandatory=$true)][string]$CertificateThumbprint
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Get-EdgeServiceProvisioningPlan {
    param([string]$InstallRoot,[string]$BindAddress,[int]$HttpsPort,[string]$TlsHostname,[string]$CertificateThumbprint)
    $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
    $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
    if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be Program Files\EnterpriseIT\<major.minor.patch>."}
    $ip=$null
    if(-not [Net.IPAddress]::TryParse($BindAddress,[ref]$ip) -or [Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any)){throw "BindAddress must be a specific non-loopback LAN address."}
    if($HttpsPort -lt 1 -or $HttpsPort -gt 65535){throw "HTTPS port is invalid."}
    if($TlsHostname -notmatch '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'){throw "TLS hostname must be a DNS hostname."}
    $thumb=($CertificateThumbprint -replace '\s','').ToUpperInvariant()
    if($thumb -notmatch '^(?:[A-F0-9]{40}|[A-F0-9]{64})$'){throw "Certificate thumbprint must be 40 or 64 hexadecimal characters."}
    [pscustomobject]@{
        ServiceName="EnterpriseITEdge";ServiceAccount="NT SERVICE\EnterpriseITEdge";ServiceSidType="unrestricted"
        InstallRoot=$root;ServiceHostPath=(Join-Path $root "EnterpriseIT.EdgeServiceHost.exe")
        BindAddress=$ip.ToString();HttpsPort=$HttpsPort;TlsHostname=$TlsHostname;CertificateThumbprint=$thumb
        ConfigRoot=(Join-Path $env:ProgramData "EnterpriseIT\Edge");ConfigPath=(Join-Path $env:ProgramData "EnterpriseIT\Edge\edge.json")
        RecoveryResetSeconds=86400;RecoveryActions='restart/60000/restart/300000/""/0';StartService=$false
    }
}
function Invoke-EdgeSc([string[]]$Arguments){& sc.exe @Arguments|Out-Null;if($LASTEXITCODE -ne 0){throw "Edge SCM provisioning failed with exit code $LASTEXITCODE."}}
function Get-EdgeCertificatePrivateKeyPath([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate) {
    $rsa=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if($null -ne $rsa) {
        try {
            if($rsa -is [Security.Cryptography.RSACng]) {
                $name=$rsa.Key.UniqueName
                if([string]::IsNullOrWhiteSpace($name)){throw "CNG certificate key has no unique name."}
                return (Join-Path $env:ProgramData ("Microsoft\Crypto\Keys\"+$name))
            }
            if($rsa -is [Security.Cryptography.RSACryptoServiceProvider]) {
                $name=$rsa.CspKeyContainerInfo.UniqueKeyContainerName
                if([string]::IsNullOrWhiteSpace($name)){throw "CSP certificate key has no unique name."}
                return (Join-Path $env:ProgramData ("Microsoft\Crypto\RSA\MachineKeys\"+$name))
            }
        } finally {$rsa.Dispose()}
    }
    $ec=[Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPrivateKey($Certificate)
    if($null -ne $ec) {
        try {
            if($ec -is [Security.Cryptography.ECDsaCng]) {
                $name=$ec.Key.UniqueName
                if([string]::IsNullOrWhiteSpace($name)){throw "CNG certificate key has no unique name."}
                return (Join-Path $env:ProgramData ("Microsoft\Crypto\Keys\"+$name))
            }
        } finally {$ec.Dispose()}
    }
    throw "Unsupported Edge certificate private-key provider; use a machine-scoped RSA or CNG ECDSA key."
}
function Invoke-EdgeServiceProvisioning {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
    param([pscustomobject]$Plan)
    if($WhatIfPreference){return [pscustomobject]@{serviceName=$Plan.ServiceName;serviceAccount=$Plan.ServiceAccount;installRoot=$Plan.InstallRoot;dryRun=$true;serviceStarted=$false}}
    if(-not(Test-Path -LiteralPath $Plan.ServiceHostPath -PathType Leaf)){throw "Required immutable Edge host payload is missing."}
    $localAddresses=@(Get-NetIPAddress -AddressFamily IPv4,IPv6 -ErrorAction Stop | ForEach-Object {$_.IPAddress})
    if($Plan.BindAddress -notin $localAddresses){throw "Configured Edge bind address is not assigned to a local interface."}
    if(Get-NetTCPConnection -LocalPort $Plan.HttpsPort -State Listen -ErrorAction SilentlyContinue){throw "Configured Edge HTTPS port is already occupied; no alternate port will be selected."}
    $cert=Get-Item ("Cert:\LocalMachine\My\"+$Plan.CertificateThumbprint) -ErrorAction Stop
    $now=Get-Date
    if(-not $cert.HasPrivateKey -or $now -lt $cert.NotBefore -or $now -ge $cert.NotAfter){throw "Edge certificate must be currently valid and have a machine private key."}
    $dns=$cert.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::DnsName,$false)
    if($dns -ine $Plan.TlsHostname){throw "Edge certificate DNS name does not exactly match TLS hostname."}
    $eku=$cert.Extensions | Where-Object {$_.Oid.Value -eq "2.5.29.37"} | Select-Object -First 1
    if($null -eq $eku -or $eku.Format($false) -notmatch "Server Authentication"){throw "Edge certificate lacks Server Authentication EKU."}
    $keyPath=Get-EdgeCertificatePrivateKeyPath -Certificate $cert
    if(-not(Test-Path -LiteralPath $keyPath -PathType Leaf)){throw "Edge certificate private-key file could not be resolved."}
    $existing=Get-CimInstance Win32_Service -Filter "Name='EnterpriseITEdge'" -ErrorAction SilentlyContinue
    if($null -eq $existing) {
        if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Create dedicated Edge virtual-account service")) {
            Invoke-EdgeSc @("create",$Plan.ServiceName,"binPath=",('"'+$Plan.ServiceHostPath+'"'),"obj=",$Plan.ServiceAccount,"start=","demand","DisplayName=","Enterprise IT TLS Edge")
        }
    } elseif($existing.PathName -notlike "*$($Plan.ServiceHostPath)*" -or $existing.StartName -ine $Plan.ServiceAccount) {throw "Existing Edge service path or identity differs; refusing replacement."}
    if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Configure enabled service SID and bounded recovery")) {
        Invoke-EdgeSc @("sidtype",$Plan.ServiceName,"unrestricted")
        Invoke-EdgeSc @("failure",$Plan.ServiceName,"reset=",[string]$Plan.RecoveryResetSeconds,"actions=",$Plan.RecoveryActions)
        Invoke-EdgeSc @("failureflag",$Plan.ServiceName,"1")
    }
    $sidOutput=(& sc.exe showsid $Plan.ServiceName 2>&1|Out-String)
    if($LASTEXITCODE -ne 0){throw "Could not resolve Edge service SID."}
    $m=[regex]::Match($sidOutput,"S-1-5-80-(?:\d+-){4}\d+")
    if(-not $m.Success){throw "SCM returned an invalid Edge service SID."}
    $sid=$m.Value
    if($PSCmdlet.ShouldProcess($Plan.InstallRoot,"Apply immutable Edge payload ACL")) {
        & icacls.exe $Plan.InstallRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)") /T|Out-Host
        if($LASTEXITCODE -ne 0){throw "Could not apply Edge payload ACL."}
    }
    if($PSCmdlet.ShouldProcess($keyPath,"Grant Edge service read access to TLS private key")) {
        & icacls.exe $keyPath /grant ("*"+$sid+":R")|Out-Null
        if($LASTEXITCODE -ne 0){throw "Could not grant Edge access to the TLS private key."}
    }
    if($PSCmdlet.ShouldProcess($Plan.ConfigPath,"Write protected Edge listener configuration")) {
        New-Item -ItemType Directory -Path $Plan.ConfigRoot -Force|Out-Null
        $json=[ordered]@{BindAddress=$Plan.BindAddress;Port=$Plan.HttpsPort;TlsHostname=$Plan.TlsHostname;CertificateThumbprint=$Plan.CertificateThumbprint}|ConvertTo-Json
        Set-Content -LiteralPath $Plan.ConfigPath -Value $json -Encoding utf8
        & icacls.exe $Plan.ConfigRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)") /T|Out-Host
        if($LASTEXITCODE -ne 0){throw "Could not protect Edge configuration ACL."}
    }
    $sidConfig=(& sc.exe qsidtype $Plan.ServiceName 2>&1|Out-String)
    if($LASTEXITCODE -ne 0 -or $sidConfig -notmatch "UNRESTRICTED"){throw "Edge service SID is not UNRESTRICTED."}
    [pscustomobject]@{serviceName=$Plan.ServiceName;serviceAccount=$Plan.ServiceAccount;serviceSid=$sid;bindAddress=$Plan.BindAddress;httpsPort=$Plan.HttpsPort;tlsHostname=$Plan.TlsHostname;privateKeyAclConfigured=$true;configAclConfigured=$true;serviceStarted=$false;firewallChanged=$false}
}
if($MyInvocation.InvocationName -ne "."){$plan=Get-EdgeServiceProvisioningPlan -InstallRoot $InstallRoot -BindAddress $BindAddress -HttpsPort $HttpsPort -TlsHostname $TlsHostname -CertificateThumbprint $CertificateThumbprint;Invoke-EdgeServiceProvisioning -Plan $plan|ConvertTo-Json -Depth 4}
