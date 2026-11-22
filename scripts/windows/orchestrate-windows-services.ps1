[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param(
 [Parameter(Mandatory=$true)][string]$InstallRoot,
 [Parameter(Mandatory=$true)][Security.SecureString]$ApiDatabaseUrl,
 [Parameter(Mandatory=$true)][Security.SecureString]$WorkerDatabaseUrl,
 [Parameter(Mandatory=$true)][string]$EdgeBindAddress,
 [int]$EdgeHttpsPort=443,
 [Parameter(Mandatory=$true)][string]$EdgeTlsHostname,
 [Parameter(Mandatory=$true)][string]$EdgeCertificateThumbprint,
 [string]$DataRoot=(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data")
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Get-WindowsServiceOrchestrationPlan {
 param([string]$InstallRoot,[string]$EdgeBindAddress,[int]$EdgeHttpsPort,[string]$EdgeTlsHostname,[string]$EdgeCertificateThumbprint,[string]$DataRoot)
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
 if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be Program Files\EnterpriseIT\<major.minor.patch>."}
 $ip=$null;if(-not [Net.IPAddress]::TryParse($EdgeBindAddress,[ref]$ip) -or [Net.IPAddress]::IsLoopback($ip) -or $ip.Equals([Net.IPAddress]::Any) -or $ip.Equals([Net.IPAddress]::IPv6Any)){throw "Edge bind address must be a specific non-loopback LAN address."}
 if($EdgeHttpsPort -lt 1 -or $EdgeHttpsPort -gt 65535){throw "Edge HTTPS port is invalid."}
 if($EdgeTlsHostname -notmatch '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'){throw "Edge TLS hostname is invalid."}
 $thumb=($EdgeCertificateThumbprint -replace '\s','').ToUpperInvariant();if($thumb -notmatch '^(?:[A-F0-9]{40}|[A-F0-9]{64})$'){throw "Edge certificate thumbprint is invalid."}
 $data=[IO.Path]::GetFullPath($DataRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pd=[IO.Path]::GetFullPath((Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18")).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $data.StartsWith(($pd+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or -not $data.EndsWith("\data",[StringComparison]::OrdinalIgnoreCase)){throw "PostgreSQL data path must be under ProgramData EnterpriseIT PostgreSQL 18 data."}
 [pscustomobject]@{
  InstallRoot=$root;DataRoot=$data;EdgeBindAddress=$ip.ToString();EdgeHttpsPort=$EdgeHttpsPort;EdgeTlsHostname=$EdgeTlsHostname;EdgeCertificateThumbprint=$thumb
  ProvisionOrder=@("EnterpriseITPostgreSQL","EnterpriseITApi","EnterpriseITWorker","EnterpriseITWeb","EnterpriseITEdge")
  StartOrder=@("EnterpriseITPostgreSQL","EnterpriseITApi","EnterpriseITWorker","EnterpriseITWeb","EnterpriseITEdge")
  Dependencies=@(
   [pscustomobject]@{Service="EnterpriseITApi";DependsOn=@("EnterpriseITPostgreSQL")},
   [pscustomobject]@{Service="EnterpriseITWorker";DependsOn=@("EnterpriseITPostgreSQL")},
   [pscustomobject]@{Service="EnterpriseITWeb";DependsOn=@("EnterpriseITApi")},
   [pscustomobject]@{Service="EnterpriseITEdge";DependsOn=@("EnterpriseITApi","EnterpriseITWeb")}
  )
  HealthEndpoints=@(
   [pscustomobject]@{Service="EnterpriseITPostgreSQL";Url="tcp://127.0.0.1:5432"},
   [pscustomobject]@{Service="EnterpriseITApi";Url="http://127.0.0.1:13001/health/ready"},
   [pscustomobject]@{Service="EnterpriseITWorker";Url="http://127.0.0.1:13002/health/ready"},
   [pscustomobject]@{Service="EnterpriseITWeb";Url="http://127.0.0.1:13000/health/ready"},
   [pscustomobject]@{Service="EnterpriseITEdge";Url=("https://"+$EdgeTlsHostname+":"+$EdgeHttpsPort+"/health/ready")}
  )
  StartServices=$true;ChangesFirewall=$false;ChangesRouter=$false;PortMapping=$false
 }
}
function Invoke-OrchestrationSc([string[]]$Arguments){& sc.exe @Arguments|Out-Null;if($LASTEXITCODE -ne 0){throw "Windows service dependency configuration failed: $LASTEXITCODE"}}
function Wait-PostgreSqlReady([string]$InstallRoot){
 $ready=Join-Path $InstallRoot "postgresql\pgsql\bin\pg_isready.exe"
 if(-not(Test-Path -LiteralPath $ready -PathType Leaf)){throw "pg_isready.exe is missing from the staged PostgreSQL payload."}
 for($i=0;$i -lt 60;$i++){& $ready -h 127.0.0.1 -p 5432 -t 2|Out-Null;if($LASTEXITCODE -eq 0){return};Start-Sleep -Seconds 1}
 throw "PostgreSQL did not become ready on 127.0.0.1:5432 within 60 seconds."
}
function Wait-HttpReady([string]$Uri,[string]$ServiceName){
 $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(3)
 try{
  for($i=0;$i -lt 60;$i++){
   try{$response=$client.GetAsync($Uri).GetAwaiter().GetResult();if($response.StatusCode -eq [Net.HttpStatusCode]::OK){$response.Dispose();return};$response.Dispose()}catch{}
   Start-Sleep -Seconds 1
  }
 }finally{$client.Dispose()}
 throw "$ServiceName did not return HTTP 200 from its readiness endpoint within 60 seconds."
}
function Get-WindowsServiceOrchestrationRequiredFiles([pscustomobject]$Plan){
 @(
  (Join-Path $Plan.InstallRoot "EnterpriseIT.ApiServiceHost.exe"),
  (Join-Path $Plan.InstallRoot "EnterpriseIT.WebServiceHost.exe"),
  (Join-Path $Plan.InstallRoot "EnterpriseIT.WorkerServiceHost.exe"),
  (Join-Path $Plan.InstallRoot "EnterpriseIT.EdgeServiceHost.exe"),
  (Join-Path $Plan.InstallRoot "runtime\node.exe"),
  (Join-Path $Plan.InstallRoot "apps\api\dist\server.js"),
  (Join-Path $Plan.InstallRoot "apps\worker\dist\main.js"),
  (Join-Path $Plan.InstallRoot "apps\web\.next\standalone\service-entry.cjs"),
  (Join-Path $Plan.InstallRoot "postgresql\pgsql\bin\postgres.exe"),
  (Join-Path $Plan.InstallRoot "postgresql\pgsql\bin\pg_ctl.exe"),
  (Join-Path $Plan.InstallRoot "postgresql\pgsql\bin\pg_isready.exe"),
  (Join-Path $Plan.DataRoot "PG_VERSION"),
  (Join-Path $Plan.DataRoot "postgresql.conf"),
  (Join-Path $Plan.DataRoot "pg_hba.conf")
 )
}
function Test-WindowsServiceOrchestrationPayload([pscustomobject]$Plan){
 $requiredFiles=@(Get-WindowsServiceOrchestrationRequiredFiles -Plan $Plan)
 $missing=@($requiredFiles|Where-Object{-not(Test-Path -LiteralPath $_ -PathType Leaf)})
 if($missing.Count -gt 0){throw "Orchestration preflight failed before service provisioning; required payload or PostgreSQL cluster files are missing: $($missing -join '; ')"}
 $version=(Get-Content -LiteralPath (Join-Path $Plan.DataRoot "PG_VERSION") -Raw).Trim()
 if($version -ne "18"){throw "Orchestration preflight requires an initialized PostgreSQL 18 data directory."}
 $postgresConfig=Get-Content -LiteralPath (Join-Path $Plan.DataRoot "postgresql.conf") -Raw
 if($postgresConfig -notmatch "(?m)^\s*listen_addresses\s*=\s*'127\.0\.0\.1'" -or $postgresConfig -notmatch "(?m)^\s*port\s*=\s*5432\s*$"){throw "Orchestration preflight requires PostgreSQL to bind only to 127.0.0.1:5432."}
 $hba=Get-Content -LiteralPath (Join-Path $Plan.DataRoot "pg_hba.conf") -Raw
 if($hba -notmatch "127\.0\.0\.1/32\s+scram-sha-256" -or $hba -notmatch "0\.0\.0\.0/0\s+reject" -or $hba -notmatch "::/0\s+reject"){throw "Orchestration preflight requires loopback-only SCRAM authentication and explicit remote IPv4/IPv6 rejection."}
 [pscustomobject]@{valid=$true;requiredFileCount=$requiredFiles.Count;postgresMajorVersion=$version;postgresListenAddress="127.0.0.1";postgresPort=5432}
}
function Start-ManagedService([string]$Name,[System.Collections.Generic.List[string]]$Started){
 $service=Get-Service -Name $Name -ErrorAction Stop
 if($service.Status -ne "Running"){Start-Service -Name $Name -ErrorAction Stop;$Started.Add($Name)}
}
function Stop-OrchestrationStartedServices([System.Collections.Generic.List[string]]$Started){
 for($i=$Started.Count-1;$i -ge 0;$i--){
  $name=$Started[$i]
  try{Stop-Service -Name $name -Force -ErrorAction Stop}
  catch{Write-Warning "Rollback could not stop $name; service remains registered and data is preserved."}
 }
}
function Invoke-WindowsServiceOrchestration([pscustomobject]$Plan,[Security.SecureString]$ApiDatabaseUrl,[Security.SecureString]$WorkerDatabaseUrl){
 if($null -eq $ApiDatabaseUrl -or $null -eq $WorkerDatabaseUrl){throw "Separate SecureString API and Worker database URLs are required."}
  Test-WindowsServiceOrchestrationPayload -Plan $Plan|Out-Null
 $resolved=@([Net.Dns]::GetHostAddresses($Plan.EdgeTlsHostname)|ForEach-Object{$_.IPAddressToString})
 if($Plan.EdgeBindAddress -notin $resolved){throw "Edge TLS hostname must resolve to the configured Edge bind address on this server."}
 # Load each guarded provisioning function only when needed; all provisioners are side-effect free under WhatIf.
 . (Join-Path $PSScriptRoot "provision-postgresql-service.ps1") -InstallRoot $Plan.InstallRoot -DataRoot $Plan.DataRoot
 $pgPlan=Get-PostgreSqlServiceProvisioningPlan -InstallRoot $Plan.InstallRoot -DataRoot $Plan.DataRoot
 Invoke-PostgreSqlServiceProvisioning -Plan $pgPlan -Confirm:$false|Out-Null
 . (Join-Path $PSScriptRoot "provision-api-service.ps1") -InstallRoot $Plan.InstallRoot
 $apiPlan=Get-ApiServiceProvisioningPlan -InstallRoot $Plan.InstallRoot
 Invoke-ApiServiceProvisioning -Plan $apiPlan -DatabaseUrl $ApiDatabaseUrl -Confirm:$false|Out-Null
 . (Join-Path $PSScriptRoot "provision-worker-service.ps1") -InstallRoot $Plan.InstallRoot
 $workerPlan=Get-WorkerServiceProvisioningPlan -InstallRoot $Plan.InstallRoot
 Invoke-WorkerServiceProvisioning -Plan $workerPlan -DatabaseUrl $WorkerDatabaseUrl -Confirm:$false|Out-Null
 . (Join-Path $PSScriptRoot "provision-web-service.ps1") -InstallRoot $Plan.InstallRoot
 $webPlan=Get-WebServiceProvisioningPlan -InstallRoot $Plan.InstallRoot
 Invoke-WebServiceProvisioning -Plan $webPlan -Confirm:$false|Out-Null
 . (Join-Path $PSScriptRoot "provision-edge-service.ps1") -InstallRoot $Plan.InstallRoot -BindAddress $Plan.EdgeBindAddress -HttpsPort $Plan.EdgeHttpsPort -TlsHostname $Plan.EdgeTlsHostname -CertificateThumbprint $Plan.EdgeCertificateThumbprint
 $edgePlan=Get-EdgeServiceProvisioningPlan -InstallRoot $Plan.InstallRoot -BindAddress $Plan.EdgeBindAddress -HttpsPort $Plan.EdgeHttpsPort -TlsHostname $Plan.EdgeTlsHostname -CertificateThumbprint $Plan.EdgeCertificateThumbprint
 Invoke-EdgeServiceProvisioning -Plan $edgePlan -Confirm:$false|Out-Null
 # SCM dependencies provide the same order on subsequent automatic boots.
 Invoke-OrchestrationSc @("config","EnterpriseITApi","depend=","EnterpriseITPostgreSQL")
 Invoke-OrchestrationSc @("config","EnterpriseITWorker","depend=","EnterpriseITPostgreSQL")
 Invoke-OrchestrationSc @("config","EnterpriseITWeb","depend=","EnterpriseITApi")
 Invoke-OrchestrationSc @("config","EnterpriseITEdge","depend=","EnterpriseITApi/EnterpriseITWeb")
 $started=[System.Collections.Generic.List[string]]::new()
 try{
  Start-ManagedService "EnterpriseITPostgreSQL" $started
  Wait-PostgreSqlReady $Plan.InstallRoot
  Start-ManagedService "EnterpriseITApi" $started
  Wait-HttpReady "http://127.0.0.1:13001/health/ready" "EnterpriseITApi"
  Start-ManagedService "EnterpriseITWorker" $started
  Wait-HttpReady "http://127.0.0.1:13002/health/ready" "EnterpriseITWorker"
  Start-ManagedService "EnterpriseITWeb" $started
  Wait-HttpReady "http://127.0.0.1:13000/health/ready" "EnterpriseITWeb"
  Start-ManagedService "EnterpriseITEdge" $started
  Wait-HttpReady ("https://"+$Plan.EdgeTlsHostname+":"+$Plan.EdgeHttpsPort+"/health/ready") "EnterpriseITEdge"
  [pscustomobject]@{status="ready";services=$Plan.StartOrder;startedByThisRun=@($started);dependenciesConfigured=$true;firewallChanged=$false;routerChanged=$false;portMapping=$false}
 }catch{
  Stop-OrchestrationStartedServices -Started $started
  throw
 }
}
if($MyInvocation.InvocationName -ne "."){
 $plan=Get-WindowsServiceOrchestrationPlan -InstallRoot $InstallRoot -EdgeBindAddress $EdgeBindAddress -EdgeHttpsPort $EdgeHttpsPort -EdgeTlsHostname $EdgeTlsHostname -EdgeCertificateThumbprint $EdgeCertificateThumbprint -DataRoot $DataRoot
 if($WhatIfPreference){$plan|ConvertTo-Json -Depth 5;return}
 if($PSCmdlet.ShouldProcess("Enterprise IT five-service deployment","Provision, configure dependencies and start in dependency order")){Invoke-WindowsServiceOrchestration -Plan $plan -ApiDatabaseUrl $ApiDatabaseUrl -WorkerDatabaseUrl $WorkerDatabaseUrl|ConvertTo-Json -Depth 5}
}
