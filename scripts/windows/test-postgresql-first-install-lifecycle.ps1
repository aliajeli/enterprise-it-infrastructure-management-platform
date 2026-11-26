# Fail-closed coverage for the PostgreSQL first-install lifecycle and the
# bootstrap capability gate. No service is registered and no cluster file is
# created by these cases: every path must stop before mutation.
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
if(-not $IsWindows){throw "Windows-only acceptance test."}
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
. (Join-Path $PSScriptRoot "orchestrate-windows-services.ps1") -InstallRoot (Join-Path $pf "EnterpriseIT\1.2.3") -ApiDatabaseUrl (ConvertTo-SecureString "unused" -AsPlainText -Force) -WorkerDatabaseUrl (ConvertTo-SecureString "unused" -AsPlainText -Force) -EdgeBindAddress "192.0.2.10" -EdgeTlsHostname "it.example.internal" -EdgeCertificateThumbprint ("A"*40)
$secret=ConvertTo-SecureString "lifecycle-synthetic-secret-1234" -AsPlainText -Force
$fullBootstrap=@{
 AdminUser="platform_admin";AdminPassword=$secret;DatabaseName="enterprise_it"
 SchemaOwnerRole="enterprise_it_owner";MigrationRole="enterprise_it_migrator";MigrationPassword=$secret
 ApiRuntimeRole="enterprise_it_api";ApiRuntimePassword=$secret
 WorkerRuntimeRole="enterprise_it_worker";WorkerRuntimePassword=$secret
}
$serviceName="EnterpriseITPostgreSQLBootstrap"
$preexistingService=Get-Service -Name $serviceName -ErrorAction SilentlyContinue
$work=Join-Path $env:TEMP ("enterpriseit-lifecycle-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work -Force|Out-Null
$versionDigits=([guid]::NewGuid().ToString("N") -replace '[^0-9]','')
if($versionDigits.Length -lt 8){throw "Could not allocate a unique test version directory."}
$installRoot=Join-Path $pf ("EnterpriseIT\0.0."+ $versionDigits)
try{
 # 1) Missing cluster without a bootstrap credential must fail closed and
 #    must not create the data directory.
 $missingPlan=[pscustomobject]@{InstallRoot=(Join-Path $work "install");DataRoot=(Join-Path $work "data")}
 $rejected=$false
 try{Invoke-PostgreSqlFirstInstallLifecycle -Plan $missingPlan -Bootstrap $null|Out-Null}catch{
  $rejected=$_.Exception.Message -like '*missing and no bootstrap credential*refusing to initialize*'
 }
 if(-not $rejected){throw "Missing cluster without bootstrap credential must be rejected."}
 if(Test-Path -LiteralPath $missingPlan.DataRoot){throw "Rejected lifecycle must not create the data directory."}

 # 2) Missing cluster with a credential but without the staged bootstrap
 #    executable must fail closed before any service registration.
 $rejected=$false
 try{Invoke-PostgreSqlFirstInstallLifecycle -Plan ([pscustomobject]@{InstallRoot=$installRoot;DataRoot=$missingPlan.DataRoot}) -Bootstrap $fullBootstrap|Out-Null}catch{
  $rejected=$_.Exception.Message -like '*Bootstrap service executable is missing*'
 }
 if(-not $rejected){throw "Missing bootstrap payload must be rejected before service registration."}
 if(Test-Path -LiteralPath $missingPlan.DataRoot){throw "Rejected lifecycle must not create the data directory."}
 if($null -eq $preexistingService -and $null -ne (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)){throw "Rejected lifecycle must not register the bootstrap service."}

 # 3) An initialized cluster without the hardened configuration must fail
 #    closed before ownership verification is attempted.
 $dataRoot=Join-Path $work "data"
 New-Item -ItemType Directory -Path $dataRoot -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $dataRoot "PG_VERSION"),"18")
 $installWithFakeExe=Join-Path $work "install"
 New-Item -ItemType Directory -Path $installWithFakeExe -Force|Out-Null
 Copy-Item -LiteralPath (Join-Path $env:SystemRoot "System32\where.exe") -Destination (Join-Path $installWithFakeExe "EnterpriseIT.PostgreSQLBootstrap.exe") -Force
 $rejected=$false
 try{Invoke-PostgreSqlFirstInstallLifecycle -Plan ([pscustomobject]@{InstallRoot=$installWithFakeExe;DataRoot=$dataRoot}) -Bootstrap $fullBootstrap|Out-Null}catch{
  $rejected=$_.Exception.Message -like '*configuration file is missing*refusing database bootstrap*'
 }
 if(-not $rejected){throw "Cluster without hardened configuration must be rejected before ownership verification."}

 # 4) Hardened pins without a working ownership-verification executable must
 #    still fail closed with the fixed verification message.
 [IO.File]::WriteAllText((Join-Path $dataRoot "postgresql.conf"),("#"+[Environment]::NewLine+"listen_addresses = '127.0.0.1'"+[Environment]::NewLine+"port = 5432"+[Environment]::NewLine))
 [IO.File]::WriteAllText((Join-Path $dataRoot "pg_hba.conf"),("host all all 127.0.0.1/32 scram-sha-256"+[Environment]::NewLine+"host all all 0.0.0.0/0 reject"+[Environment]::NewLine+"host all all ::/0 reject"+[Environment]::NewLine))
 $rejected=$false
 $observedVerifyFailure=""
 try{Invoke-PostgreSqlFirstInstallLifecycle -Plan ([pscustomobject]@{InstallRoot=$installWithFakeExe;DataRoot=$dataRoot}) -Bootstrap $fullBootstrap|Out-Null}catch{
  $rejected=$_.Exception.Message -like '*PostgreSQL cluster ownership verification failed*refusing to adopt*'
  if(-not $rejected){$observedVerifyFailure=$_.Exception.Message}
 }
 if(-not $rejected){throw "Ownership verification failure must be fail-closed with the fixed message. Observed: $observedVerifyFailure"}

 # 5) The verification executable must exist before any verify invocation.
 $rejected=$false
 try{Invoke-PostgreSqlFirstInstallLifecycle -Plan ([pscustomobject]@{InstallRoot=(Join-Path $work "empty-install");DataRoot=$dataRoot}) -Bootstrap $fullBootstrap|Out-Null}catch{
  $rejected=$_.Exception.Message -like '*ownership verification executable is missing*'
 }
 if(-not $rejected){throw "Missing verification executable must be rejected before invocation."}

 # 6) State detection edges: empty directory is missing, stray content and
 #    unsupported major versions are rejected, valid layout is initialized.
 $state=Get-PostgreSqlClusterState -DataRoot (Join-Path $work "absent")
 if($state.state -ne "missing"){throw "Absent data directory must report missing state."}
 $emptyDir=Join-Path $work "empty-dir"
 New-Item -ItemType Directory -Path $emptyDir -Force|Out-Null
 $state=Get-PostgreSqlClusterState -DataRoot $emptyDir
 if($state.state -ne "missing"){throw "Empty data directory must report missing state."}
 $strayDir=Join-Path $work "stray-dir"
 New-Item -ItemType Directory -Path $strayDir -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $strayDir "stray.txt"),"x")
 $rejected=$false
 try{Get-PostgreSqlClusterState -DataRoot $strayDir|Out-Null}catch{$rejected=$_.Exception.Message -like '*without a recognized cluster*refusing to adopt*'}
 if(-not $rejected){throw "Non-empty uninitialized data directory must be rejected."}
 $versionDir=Join-Path $work "version-dir"
 New-Item -ItemType Directory -Path $versionDir -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $versionDir "PG_VERSION"),"17")
 $rejected=$false
 try{Get-PostgreSqlClusterState -DataRoot $versionDir|Out-Null}catch{$rejected=$_.Exception.Message -like '*major version must be 18*'}
 if(-not $rejected){throw "Unsupported cluster major version must be rejected."}
 $state=Get-PostgreSqlClusterState -DataRoot $dataRoot
 if($state.state -ne "initialized"){throw "Hardened cluster fixture must report initialized state."}

 # 7) Service identities derive to the pinned SHA1 vectors (identical to the
 #    native executable and `sc showsid`) without requiring registration.
 $expectedServiceSids=@{
  "EnterpriseITPostgreSQLBootstrap"="S-1-5-80-2898200459-3236970252-1070820519-1144135147-264584976"
  "EnterpriseITPostgreSQL"="S-1-5-80-2114905006-2325062578-1701378398-3453278453-1022961949"
 }
 foreach($name in @("EnterpriseITPostgreSQLBootstrap","EnterpriseITPostgreSQL")){
  $sid=Resolve-PostgreSqlServiceSid -ServiceName $name
  if($sid -cne $expectedServiceSids[$name]){throw "Resolved service identity for $name does not match the pinned cross-implementation vector."}
 }

 # 8) The bootstrap capability gate opens only for a complete, valid input
 #    set and fails closed on incomplete or colliding definitions.
 Assert-PostgreSqlBootstrapCapability -Bootstrap $fullBootstrap
 Assert-PostgreSqlBootstrapCapability -Bootstrap $null
 $rejected=$false
 try{Assert-PostgreSqlBootstrapCapability -Bootstrap @{}}catch{$rejected=$_.Exception.Message -like '*capability prerequisites are not satisfied*'}
 if(-not $rejected){throw "Empty bootstrap capability must be rejected."}
 $incomplete=$fullBootstrap.Clone()
 $incomplete.Remove("MigrationPassword")
 $rejected=$false
 try{Assert-PostgreSqlBootstrapCapability -Bootstrap $incomplete}catch{$rejected=$_.Exception.Message -like '*capability prerequisites are not satisfied*'}
 if(-not $rejected){throw "Incomplete bootstrap capability must be rejected."}
 $colliding=$fullBootstrap.Clone()
 $colliding["WorkerRuntimeRole"]="enterprise_it_api"
 $rejected=$false
 try{Assert-PostgreSqlBootstrapCapability -Bootstrap $colliding}catch{$rejected=$_.Exception.Message -like '*roles must be distinct*'}
 if(-not $rejected){throw "Colliding bootstrap roles must be rejected."}

 # 9) WhatIf lifecycle is read-only and reports the observed state.
 $dry=Invoke-PostgreSqlFirstInstallLifecycle -Plan ([pscustomobject]@{InstallRoot=$installRoot;DataRoot=$dataRoot}) -Bootstrap $fullBootstrap -WhatIf
 if($dry.status -ne "whatif" -or $dry.clusterState -ne "initialized" -or $dry.ownershipVerified){throw "Lifecycle WhatIf must be read-only."}

 Write-Host "PostgreSQL first-install lifecycle fail-closed tests passed."
}finally{
 if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
}
