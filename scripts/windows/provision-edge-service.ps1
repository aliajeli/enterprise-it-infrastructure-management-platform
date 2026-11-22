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
function Test-EdgeServicePreflightFacts([pscustomobject]$Plan,[pscustomobject]$Facts){
 if(-not $Facts.HostPayloadExists){throw "Edge host payload is missing."}
 if($Plan.BindAddress -notin @($Facts.LocalAddresses)){throw "Edge bind IP is not assigned to a local interface."}
 if($Facts.PortOccupied){throw "HTTPS port is occupied; no alternate port will be selected."}
 if(-not $Facts.CertificateFound){throw "Edge certificate was not found in the LocalMachine My store."}
 if(-not $Facts.HasPrivateKey -or $Facts.Now -lt $Facts.NotBefore -or $Facts.Now -ge $Facts.NotAfter){throw "Edge certificate must be valid and have a machine private key."}
 if($Facts.DnsName -ine $Plan.TlsHostname){throw "Certificate DNS name does not match configured hostname."}
 if(-not $Facts.ServerAuthenticationEku){throw "Certificate lacks Server Authentication EKU."}
 if(-not $Facts.ChainValid){throw "Edge certificate chain is not trusted by the LocalMachine certificate stores."}
 if($Facts.PrivateKeyProvider -notin @("RSA-CNG","RSA-CSP") -or -not $Facts.PrivateKeyFileExists){throw "Edge certificate must use a supported machine RSA private-key provider with an accessible key file."}
 [pscustomobject]@{valid=$true;certificateThumbprint=$Plan.CertificateThumbprint;tlsHostname=$Plan.TlsHostname;chainValid=$true;privateKeyProvider=$Facts.PrivateKeyProvider}
}
function Test-EdgeServicePreflight([pscustomobject]$Plan){
 $cert=Get-Item ("Cert:\LocalMachine\My\"+$Plan.CertificateThumbprint) -ErrorAction SilentlyContinue
 $rsa=$null;$key=$null;$provider="Unsupported"
 if($null -ne $cert){
  $rsa=$cert.PrivateKey
  if($rsa -is [Security.Cryptography.RSACng]){$provider="RSA-CNG";$key=Join-Path $env:ProgramData ("Microsoft\Crypto\Keys\"+$rsa.Key.UniqueName)}
  elseif($rsa -is [Security.Cryptography.RSACryptoServiceProvider]){$provider="RSA-CSP";$key=Join-Path $env:ProgramData ("Microsoft\Crypto\RSA\MachineKeys\"+$rsa.CspKeyContainerInfo.UniqueKeyContainerName)}
 }
 $eku=$null
 if($null -ne $cert){$eku=$cert.Extensions|Where-Object{$_.Oid.Value -eq "2.5.29.37"}|Select-Object -First 1}
 $chainValid=$false
 if($null -ne $cert){
  $chain=[Security.Cryptography.X509Certificates.X509Chain]::new()
  try{$chain.ChainPolicy.RevocationMode=[Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck;$chain.ChainPolicy.VerificationFlags=[Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag;$chainValid=$chain.Build($cert)}
  finally{$chain.Dispose()}
 }
 $facts=[pscustomobject]@{
  HostPayloadExists=(Test-Path -LiteralPath $Plan.ServiceHostPath -PathType Leaf)
  LocalAddresses=@(Get-NetIPAddress -ErrorAction Stop|ForEach-Object{$_.IPAddress})
  PortOccupied=($null -ne (Get-NetTCPConnection -LocalPort $Plan.HttpsPort -State Listen -ErrorAction SilentlyContinue|Select-Object -First 1))
  CertificateFound=($null -ne $cert)
  HasPrivateKey=($null -ne $cert -and $cert.HasPrivateKey)
  Now=Get-Date
  NotBefore=if($null -ne $cert){$cert.NotBefore}else{[DateTime]::MinValue}
  NotAfter=if($null -ne $cert){$cert.NotAfter}else{[DateTime]::MinValue}
  DnsName=if($null -ne $cert){$cert.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::DnsName,$false)}else{""}
  ServerAuthenticationEku=($null -ne $eku -and $eku.Format($false) -match "Server Authentication")
  ChainValid=$chainValid
  PrivateKeyProvider=$provider
  PrivateKeyFileExists=($null -ne $key -and (Test-Path -LiteralPath $key -PathType Leaf))
 }
 $result=Test-EdgeServicePreflightFacts -Plan $Plan -Facts $facts
 [pscustomobject]@{valid=$result.valid;certificate=$cert;privateKeyPath=$key;privateKeyProvider=$provider;chainValid=$chainValid}
}
function Invoke-EdgeSc([string[]]$a){& sc.exe @a|Out-Null;if($LASTEXITCODE -ne 0){throw "Edge SCM operation failed: $LASTEXITCODE"}}
function Invoke-EdgeServiceProvisioning{
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]param([pscustomobject]$Plan)
 if($WhatIfPreference){return [pscustomobject]@{serviceName=$Plan.ServiceName;dryRun=$true;serviceStarted=$false}}
 $preflight=Test-EdgeServicePreflight -Plan $Plan
 $cert=$preflight.certificate
 $service=Get-CimInstance Win32_Service -Filter "Name='EnterpriseITEdge'" -ErrorAction SilentlyContinue
 if($null -eq $service){if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Create Edge virtual-account service")){Invoke-EdgeSc @("create",$Plan.ServiceName,"binPath=",('"'+$Plan.ServiceHostPath+'"'),"obj=","NT SERVICE\EnterpriseITEdge","start=","auto","DisplayName=","Enterprise IT TLS Edge")}}
 elseif($service.PathName -notlike "*$($Plan.ServiceHostPath)*" -or $service.StartName -ine "NT SERVICE\EnterpriseITEdge"){throw "Existing Edge service path or identity differs; refusing replacement."}
 if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Configure service SID and bounded recovery")){Invoke-EdgeSc @("sidtype",$Plan.ServiceName,"unrestricted");Invoke-EdgeSc @("failure",$Plan.ServiceName,"reset=","86400","actions=",$Plan.RecoveryActions);Invoke-EdgeSc @("failureflag",$Plan.ServiceName,"1")}
 $sidText=(& sc.exe showsid $Plan.ServiceName 2>&1|Out-String);if($LASTEXITCODE -ne 0){throw "Could not resolve Edge service SID."};$m=[regex]::Match($sidText,"S-1-5-80-(?:\d+-){4}\d+");if(-not $m.Success){throw "Invalid Edge service SID."};$sid=$m.Value
 if($PSCmdlet.ShouldProcess($Plan.InstallRoot,"Apply immutable Edge payload ACL")){& icacls.exe $Plan.InstallRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)") /T|Out-Host;if($LASTEXITCODE -ne 0){throw "Edge payload ACL failed."}}
 $key=$preflight.privateKeyPath
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
