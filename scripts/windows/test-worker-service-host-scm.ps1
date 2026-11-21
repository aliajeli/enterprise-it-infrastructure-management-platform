$ErrorActionPreference="Stop"
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$root=Join-Path $env:RUNNER_TEMP "enterprise-it-worker-scm-smoke"
$runtime=Join-Path $root "runtime"
$workerDirectory=Join-Path $root "apps\worker\dist"
$serviceName="EnterpriseITWorker"
$hostProject=Join-Path $repoRoot "apps\worker\windows\service-host\EnterpriseIT.WorkerServiceHost.csproj"
$stubProject=Join-Path $repoRoot "apps\worker\windows\service-host-smoke\WindowsWorkerStub.csproj"
$hostExe=Join-Path $root "EnterpriseIT.WorkerServiceHost.exe"
$entry=Join-Path $workerDirectory "main.js"
$configRoot=Join-Path $env:ProgramData "EnterpriseIT\Worker"
$configPath=Join-Path $configRoot "database.config.dpapi"
$serviceCreated=$false;$configCreated=$false
function Invoke-WorkerSmokeSc([string[]]$Arguments){& sc.exe @Arguments|Out-Null;if($LASTEXITCODE-ne 0){throw "sc.exe operation failed: $($Arguments -join ' '): $LASTEXITCODE"}}
function Get-WorkerSmokeChild {@(Get-CimInstance Win32_Process|Where-Object{$_.CommandLine-and $_.CommandLine.Contains($entry,[StringComparison]::OrdinalIgnoreCase)})}
try{
 if(Test-Path $root){Remove-Item $root -Recurse -Force}
 if(Test-Path $configRoot){throw "Worker DPAPI smoke config directory already exists; refusing overwrite."}
 dotnet publish $hostProject --configuration Release --output $root
 if($LASTEXITCODE-ne 0){throw "Publishing Worker service host failed."}
 New-Item -ItemType Directory -Path $runtime -Force|Out-Null
 New-Item -ItemType Directory -Path $workerDirectory -Force|Out-Null
 dotnet build $stubProject --configuration Release --output $runtime
 if($LASTEXITCODE-ne 0){throw "Building Worker SCM stub failed."}
 $stubExe=Join-Path $runtime "WindowsWorkerStub.exe"
 if(-not(Test-Path $stubExe)){throw "Worker SCM stub executable is missing."}
 Copy-Item $stubExe (Join-Path $runtime "node.exe") -Force
 Set-Content -LiteralPath $entry -Value "READY" -Encoding ascii
 if(-not(Test-Path $hostExe)){throw "Worker service-host executable is missing."}
 & sc.exe query $serviceName 2>&1|Out-Null;if($LASTEXITCODE-eq 0){throw "Service $serviceName already exists; refusing overwrite."}
 Invoke-WorkerSmokeSc @("create",$serviceName,"obj=","NT AUTHORITY\LocalService","binPath=",$hostExe,"start=","demand")
 $serviceCreated=$true
 Invoke-WorkerSmokeSc @("sidtype",$serviceName,"unrestricted")
 $sidOutput=(& sc.exe showsid $serviceName 2>&1|Out-String);if($LASTEXITCODE-ne 0){throw "Could not query Worker service SID."}
 $match=[regex]::Match($sidOutput,"S-1-5-80-(?:\d+-){4}\d+");if(-not $match.Success){throw "SCM did not return a valid Worker service SID."};$sid=$match.Value
 & icacls.exe $root /grant ("*"+$sid+":(OI)(CI)(RX)") /T|Out-Null;if($LASTEXITCODE-ne 0){throw "Could not grant Worker service SID access to smoke payload."}
 New-Item -ItemType Directory -Path $configRoot -Force|Out-Null
 & icacls.exe $configRoot /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" ("*"+$sid+":(OI)(CI)(RX)")|Out-Null
 if($LASTEXITCODE-ne 0){throw "Could not protect Worker smoke config directory."};$configCreated=$true
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$hostExe;$info.Arguments='--provision-database-config "'+$configPath+'"';$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $proc=[Diagnostics.Process]::Start($info);$proc.StandardInput.Write("postgresql://smoke:secret@127.0.0.1:5432/smoke");$proc.StandardInput.Close()
 $outTask=$proc.StandardOutput.ReadToEndAsync();$errTask=$proc.StandardError.ReadToEndAsync();$proc.WaitForExit();$out=$outTask.GetAwaiter().GetResult();$err=$errTask.GetAwaiter().GetResult();$proc.Dispose()
 if($out.Trim()-ne "OK"-or $err.Length-ne 0-or -not(Test-Path $configPath)){throw "Worker DPAPI smoke configuration failed."}
 Start-Service -Name $serviceName
 $deadline=[DateTime]::UtcNow.AddSeconds(35)
 do{$state=(Get-Service -Name $serviceName).Status;if($state-eq "Running"){break};if($state-eq "Stopped"){throw "Worker service stopped before reaching Running."};Start-Sleep -Milliseconds 500}while([DateTime]::UtcNow-lt $deadline)
 if((Get-Service -Name $serviceName).Status-ne "Running"){throw "Worker service did not reach Running."}
 $childDeadline=[DateTime]::UtcNow.AddSeconds(10)
 do{$children=Get-WorkerSmokeChild;if($children.Count-eq 1){break};Start-Sleep -Milliseconds 250}while([DateTime]::UtcNow-lt $childDeadline)
 if($children.Count-ne 1){throw "Expected one Worker child after SCM startup; found $($children.Count)."}
 $ready=$false
 for($i=0;$i-lt 20;$i++){try{$response=Invoke-WebRequest -Uri "http://127.0.0.1:13002/health/ready" -UseBasicParsing -TimeoutSec 2;if($response.StatusCode-eq 200){$ready=$true;break}}catch{};Start-Sleep -Milliseconds 500}
 if(-not $ready){throw "Worker loopback readiness endpoint did not return HTTP 200."}
 Stop-Service -Name $serviceName
 $stopDeadline=[DateTime]::UtcNow.AddSeconds(30)
 do{if((Get-Service -Name $serviceName).Status-eq "Stopped"){break};Start-Sleep -Milliseconds 500}while([DateTime]::UtcNow-lt $stopDeadline)
 if((Get-Service -Name $serviceName).Status-ne "Stopped"){throw "Worker service did not stop within 30 seconds."}
 $childDeadline=[DateTime]::UtcNow.AddSeconds(10)
 do{$children=Get-WorkerSmokeChild;if($children.Count-eq 0){break};Start-Sleep -Milliseconds 250}while([DateTime]::UtcNow-lt $childDeadline)
 if($children.Count-ne 0){throw "Worker child remained after SCM reported Stopped."}
 Write-Host "Worker SCM smoke passed: service SID, DPAPI config, readiness, graceful shutdown and child reap."
}finally{
 if($serviceCreated){try{$state=(Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status;if($state-and $state-ne "Stopped"){Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue;Start-Sleep -Seconds 2}}catch{};& sc.exe delete $serviceName|Out-Null}
 if($configCreated-and(Test-Path $configRoot)){Remove-Item $configRoot -Recurse -Force -ErrorAction SilentlyContinue}
 if(Test-Path $root){Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue}
}
