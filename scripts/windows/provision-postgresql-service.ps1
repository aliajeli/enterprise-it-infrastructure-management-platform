[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param([Parameter(Mandatory=$true)][string]$InstallRoot,[string]$DataRoot=(Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18\data"))
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Get-PostgreSqlServiceProvisioningPlan([string]$InstallRoot,[string]$DataRoot){
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "PostgreSQL binaries must be beneath Program Files."}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
 if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be versioned Program Files payload."}
 $data=[IO.Path]::GetFullPath($DataRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pd=[IO.Path]::GetFullPath((Join-Path $env:ProgramData "EnterpriseIT\PostgreSQL\18")).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $data.StartsWith(($pd+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or -not $data.EndsWith("\data",[StringComparison]::OrdinalIgnoreCase)){throw "PostgreSQL data must be beneath ProgramData EnterpriseIT PostgreSQL 18 data."}
 [pscustomobject]@{ServiceName="EnterpriseITPostgreSQL";ServiceAccount="NT SERVICE\EnterpriseITPostgreSQL";InstallRoot=$root;DataRoot=$data;PostgresPath=(Join-Path $root "postgresql\pgsql\bin\postgres.exe");PgCtlPath=(Join-Path $root "postgresql\pgsql\bin\pg_ctl.exe");RecoveryActions='restart/60000/restart/300000/""/0';StartService=$false;ListenAddress="127.0.0.1";Port=5432}
}
function Invoke-PostgreSqlSc([string[]]$a){& sc.exe @a|Out-Null;if($LASTEXITCODE -ne 0){throw "PostgreSQL SCM operation failed: $LASTEXITCODE"}}
function Invoke-PostgreSqlServiceProvisioning{
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]param([pscustomobject]$Plan)
 if($WhatIfPreference){return [pscustomobject]@{serviceName=$Plan.ServiceName;serviceAccount=$Plan.ServiceAccount;installRoot=$Plan.InstallRoot;dataRoot=$Plan.DataRoot;dryRun=$true;serviceStarted=$false}}
 foreach($f in @($Plan.PostgresPath,$Plan.PgCtlPath,(Join-Path $Plan.DataRoot "PG_VERSION"),(Join-Path $Plan.DataRoot "postgresql.conf"),(Join-Path $Plan.DataRoot "pg_hba.conf"))){if(-not(Test-Path -LiteralPath $f -PathType Leaf)){throw "Required PostgreSQL binary or initialized cluster file is missing."}}
 if((Get-Content (Join-Path $Plan.DataRoot "PG_VERSION") -Raw).Trim() -ne "18"){throw "PostgreSQL data directory major version must be 18."}
 $conf=Get-Content (Join-Path $Plan.DataRoot "postgresql.conf") -Raw
 if($conf -notmatch "(?m)^\s*listen_addresses\s*=\s*'127\.0\.0\.1'" -or $conf -notmatch "(?m)^\s*port\s*=\s*5432\s*$"){throw "PostgreSQL must bind only to 127.0.0.1:5432."}
 $hba=Get-Content (Join-Path $Plan.DataRoot "pg_hba.conf") -Raw
 if($hba -notmatch "127\.0\.0\.1/32\s+scram-sha-256" -or $hba -notmatch "0\.0\.0\.0/0\s+reject" -or $hba -notmatch "::/0\s+reject"){throw "PostgreSQL pg_hba policy is not loopback-only SCRAM."}
 if(Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue){throw "TCP 5432 is occupied; no alternate port will be selected."}
 $existing=Get-CimInstance Win32_Service -Filter "Name='EnterpriseITPostgreSQL'" -ErrorAction SilentlyContinue
 if($null -eq $existing){
  $bin='"'+$Plan.PgCtlPath+'" runservice -N "EnterpriseITPostgreSQL" -D "'+$Plan.DataRoot+'" -w'
  if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Register native PostgreSQL service with dedicated virtual account")){Invoke-PostgreSqlSc @("create",$Plan.ServiceName,"binPath=",$bin,"obj=",$Plan.ServiceAccount,"start=","demand","DisplayName=","Enterprise IT PostgreSQL 18")}
 }elseif($existing.PathName -notlike "*$($Plan.PgCtlPath)*" -or $existing.PathName -notlike "*$($Plan.DataRoot)*" -or $existing.StartName -ine $Plan.ServiceAccount){throw "Existing PostgreSQL service path, data directory or identity differs; refusing replacement."}
 if($PSCmdlet.ShouldProcess($Plan.ServiceName,"Configure service SID and bounded recovery")){Invoke-PostgreSqlSc @("sidtype",$Plan.ServiceName,"unrestricted");Invoke-PostgreSqlSc @("failure",$Plan.ServiceName,"reset=","86400","actions=",$Plan.RecoveryActions);Invoke-PostgreSqlSc @("failureflag",$Plan.ServiceName,"1")}
 $sidText=(& sc.exe showsid $Plan.ServiceName 2>&1|Out-String);if($LASTEXITCODE -ne 0){throw "Could not resolve PostgreSQL service SID."}
 $m=[regex]::Match($sidText,"S-1-5-80-(?:\d+-){4}\d+");if(-not $m.Success){throw "Invalid PostgreSQL service SID."};$sid=$m.Value
 if($PSCmdlet.ShouldProcess($Plan.InstallRoot,"Apply immutable PostgreSQL binary ACL")){& icacls.exe $Plan.InstallRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)") /T|Out-Host;if($LASTEXITCODE -ne 0){throw "PostgreSQL binary ACL failed."}}
 if($PSCmdlet.ShouldProcess($Plan.DataRoot,"Apply PostgreSQL data ACL")){& icacls.exe $Plan.DataRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(M)") /T|Out-Host;if($LASTEXITCODE -ne 0){throw "PostgreSQL data ACL failed."}}
 $sidState=(& sc.exe qsidtype $Plan.ServiceName 2>&1|Out-String);if($LASTEXITCODE -ne 0 -or $sidState -notmatch "UNRESTRICTED"){throw "PostgreSQL service SID is not unrestricted."}
 [pscustomobject]@{serviceName=$Plan.ServiceName;serviceAccount=$Plan.ServiceAccount;serviceSid=$sid;version="18.7";listenAddress="127.0.0.1";port=5432;dataAclConfigured=$true;serviceStarted=$false;firewallChanged=$false}|ConvertTo-Json -Depth 3
}
if($MyInvocation.InvocationName -ne "."){$p=Get-PostgreSqlServiceProvisioningPlan -InstallRoot $InstallRoot -DataRoot $DataRoot;Invoke-PostgreSqlServiceProvisioning -Plan $p}
