[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param([Parameter(Mandatory=$true)][string]$InstallRoot,[Parameter(Mandatory=$true)][string]$BindAddress,[int]$HttpsPort=443,[Parameter(Mandatory=$true)][string]$TlsHostname,[Parameter(Mandatory=$true)][string]$CertificateThumbprint)
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
function Get-EdgeServiceProvisioningPlan([string]$InstallRoot,[string]$BindAddress,[int]$HttpsPort,[string]$TlsHostname,[string]$CertificateThumbprint){
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar);$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar);if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be versioned Program Files payload."}
 $ip=$null;if(-not [Net.IPAddress]::TryParse($BindAddress,[ref]$ip) -or [Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any)){throw "BindAddress must be a specific non-loopback LAN address."}
 if($HttpsPort -lt 1 -or $HttpsPort -gt 65535){throw "HTTPS port is invalid."}
 if($TlsHostname -notmatch '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'){throw "TLS hostname is invalid."}
 $thumb=($CertificateThumbprint -replace '\s','').ToUpperInvariant();if($thumb -notmatch '^(?:[A-F0-9]{40}|[A-F0-9]{64})$'){throw "Certificate thumbprint is invalid."}
 [pscustomobject]@{ServiceName="EnterpriseITEdge";ServiceAccount="NT SERVICE\EnterpriseITEdge";InstallRoot=$root;ServiceHostPath=(Join-Path $root "EnterpriseIT.EdgeServiceHost.exe");BindAddress=$ip.ToString();HttpsPort=$HttpsPort;TlsHostname=$TlsHostname;CertificateThumbprint=$thumb;ConfigRoot=(Join-Path $env:ProgramData "EnterpriseIT\Edge");ConfigPath=(Join-Path $env:ProgramData "EnterpriseIT\Edge\edge.json");StartService=$false;RecoveryResetSeconds=86400;RecoveryActions='restart/60000/restart/300000/""/0'}
}
function Invoke-EdgeSc([string[]]$a){& sc.exe @a|Out-Null;if($LASTEXITCODE -ne 0){throw "Edge SCM operation failed: $LASTEXITCODE"}}
function Invoke-EdgeServiceProvisioning{
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]param([pscustomobject]$Plan)
 if($WhatIfPreference){return [pscustomobject]@{serviceName=$Plan.ServiceName;dryRun=$true;serviceStarted=$false}}
 if(-not(Test-Path $Plan.ServiceHostPath -PathType Leaf)){throw "Edge host payload is missing."}
 $ips=@(Get-NetIPAddress -ErrorAction Stop|ForEach-Object{$_.IPAddress});if($Plan.BindAddress -notin $ips){throw "Edge bind IP is not assigned to a local interface."}
 if(Get-NetTCPConnection -LocalPort $Plan.HttpsPort -State Listen -ErrorAction SilentlyContinue){throw "HTTPS port is occupied; no alternate port will be selected."}
 $cert=Get-Item ("Cert:\LocalMachine\My\"+$Plan.CertificateThumbprint) -ErrorAction Stop;$now=Get-Date
 if(-not $cert.HasPrivateKey -or $now -lt $cert.NotBefore -or $now -ge $cert.NotAfter){throw "Edge certificate must be valid and have a machine private key."}
 if($cert.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::DnsName,$false) -ine $Plan.TlsHostname){throw "Certificate DNS name does not match configured hostname."}
 $eku=$cert.Extensions|Where-Object{$_.Oid.Value -eq "2.5.29.37"}|Select-Object -First 1;if($null -eq $eku -or $eku.Format($false) -notmatch "Server Authentication"){throw "Certificate lacks Server Authentication EKU."}
 $service=Get-CimInstance Win32_Service -Filter "Name='EnterpriseITEdge'" -ErrorAction SilentlyContinue
 if($null -eq $service){if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Create Edge virtual-account service")){Invoke-EdgeSc @("create",$Plan.ServiceName,"binPath=",('"'+$Plan.ServiceHostPath+'"'),"obj=","NT SERVICE\EnterpriseITEdge","start=","demand","DisplayName=","Enterprise IT TLS Edge")}}
 elseif($service.PathName -notlike "*$($Plan.ServiceHostPath)*" -or $service.StartName -ine "NT SERVICE\EnterpriseITEdge"){throw "Existing Edge service path or identity differs; refusing replacement."}
 if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Configure service SID and bounded recovery")){Invoke-EdgeSc @("sidtype",$Plan.ServiceName,"unrestricted");Invoke-EdgeSc @("failure",$Plan.ServiceName,"reset=","86400","actions=",$Plan.RecoveryActions);Invoke-EdgeSc @("failureflag",$Plan.ServiceName,"1")}
 $sidText=(& sc.exe showsid $Plan.ServiceName 2>&1|Out-String);if($LASTEXITCODE -ne 0){throw "Could not resolve Edge service SID."};$m=[regex]::Match($sidText,"S-1-5-80-(?:\d+-){4}\d+");if(-not $m.Success){throw "Invalid Edge service SID."};$sid=$m.Value
 if($PSCmdlet.ShouldProcess($Plan.InstallRoot,"Apply immutable Edge payload ACL")){& icacls.exe $Plan.InstallRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)") /T|Out-Host;if($LASTEXITCODE -ne 0){throw "Edge payload ACL failed."}}
 $key=$null;$rsa=$cert.PrivateKey
 if($rsa -is [Security.Cryptography.RSACng]){$key=Join-Path $env:ProgramData ("Microsoft\Crypto\Keys\"+$rsa.Key.UniqueName)}
 elseif($rsa -is [Security.Cryptography.RSACryptoServiceProvider]){$key=Join-Path $env:ProgramData ("Microsoft\Crypto\RSA\MachineKeys\"+$rsa.CspKeyContainerInfo.UniqueKeyContainerName)}
 else{throw "Unsupported certificate private-key provider; use machine RSA CNG or CSP."}
 if(-not(Test-Path $key -PathType Leaf)){throw "Machine private-key file could not be resolved."}
 if($PSCmdlet.ShouldProcess($key,"Grant Edge service private-key read access")){& icacls.exe $key /grant ("*"+$sid+":R")|Out-Null;if($LASTEXITCODE -ne 0){throw "Private-key ACL update failed."}}
 if($PSCmdlet.ShouldProcess($Plan.ConfigPath,"Write protected Edge listener configuration")){
  New-Item -ItemType Directory -Path $Plan.ConfigRoot -Force|Out-Null
  [ordered]@{BindAddress=$Plan.BindAddress;Port=$Plan.HttpsPort;TlsHostname=$Plan.TlsHostname;CertificateThumbprint=$Plan.CertificateThumbprint}|ConvertTo-Json|Set-Content -LiteralPath $Plan.ConfigPath -Encoding utf8
  & icacls.exe $Plan.ConfigRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)") /T|Out-Host;if($LASTEXITCODE -ne 0){throw "Edge config ACL update failed."}
 }
 $sidState=(& sc.exe qsidtype $Plan.ServiceName 2>&1|Out-String);if($LASTEXITCODE -ne 0 -or $sidState -notmatch "UNRESTRICTED"){throw "Edge service SID is not unrestricted."}
 [pscustomobject]@{serviceName=$Plan.ServiceName;serviceAccount="NT SERVICE\EnterpriseITEdge";serviceSid=$sid;bindAddress=$Plan.BindAddress;httpsPort=$Plan.HttpsPort;privateKeyAclConfigured=$true;configAclConfigured=$true;serviceStarted=$false;firewallChanged=$false}
}
if($MyInvocation.InvocationName -ne "."){$p=Get-EdgeServiceProvisioningPlan -InstallRoot $InstallRoot -BindAddress $BindAddress -HttpsPort $HttpsPort -TlsHostname $TlsHostname -CertificateThumbprint $CertificateThumbprint;Invoke-EdgeServiceProvisioning -Plan $p|ConvertTo-Json -Depth 3}
