[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$InstallRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Get-NodeApplicationRuntimeStagePlan {
 [CmdletBinding()]param([string]$SourceRoot,[string]$InstallRoot)
 $source=[IO.Path]::GetFullPath($SourceRoot);$root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw "Install root must be beneath Program Files."}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
 if($parts.Length -ne 2 -or $parts[0] -ne "EnterpriseIT" -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw "Install root must be Program Files\EnterpriseIT\<major.minor.patch>."}
 foreach($file in @("package.json","package-lock.json","apps\api\package.json","apps\worker\package.json","packages\database\package.json","apps\api\dist\server.js","apps\worker\dist\main.js","packages\database\dist\index.js","packages\database\prisma\schema.prisma","packages\database\prisma.config.ts")){if(-not(Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)){throw "Required application runtime source is missing: $file"}}
 if(-not(Test-Path -LiteralPath (Join-Path $source "packages\database\prisma\migrations") -PathType Container)){throw "Required Prisma migrations directory is missing."}
 $destinations=@((Join-Path $root "node_modules"),(Join-Path $root "apps\api"),(Join-Path $root "apps\worker"),(Join-Path $root "packages\database"))
 foreach($destination in $destinations){if(Test-Path -LiteralPath $destination){throw "Application runtime destination already exists; refusing to overwrite: $destination"}}
 $node=Join-Path $root "runtime\node.exe";$npm=Join-Path $root "runtime\npm.cmd"
 if(-not(Test-Path -LiteralPath $node -PathType Leaf) -or -not(Test-Path -LiteralPath $npm -PathType Leaf)){throw "Stage bundled Node.js 26 runtime (node.exe and npm.cmd) before application runtime staging."}
 $nodeVersion=(& $node --version 2>&1|Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v26\.'){throw "Application runtime staging requires bundled Node.js 26; received '$nodeVersion'."}
 [pscustomobject]@{SourceRoot=$source;InstallRoot=$root;NodeVersion=$nodeVersion;Destinations=$destinations;Workspaces=@("@platform/api","@platform/worker","@platform/database");Immutable=$true}
}
if($MyInvocation.InvocationName -ne "."){
 $plan=Get-NodeApplicationRuntimeStagePlan -SourceRoot $SourceRoot -InstallRoot $InstallRoot
 if($WhatIfPreference){[pscustomobject]@{installRoot=$plan.InstallRoot;nodeVersion=$plan.NodeVersion;workspaces=$plan.Workspaces;overwrite=$false;dryRun=$true}|ConvertTo-Json -Depth 4;return}
 if(-not $PSCmdlet.ShouldProcess($plan.InstallRoot,"Build and stage immutable API/Worker production runtime")){return}
 $temp=Join-Path ([IO.Path]::GetTempPath()) ("enterpriseit-app-runtime-"+[guid]::NewGuid().ToString("N"))
 $promoted=[System.Collections.Generic.List[string]]::new();$previousDatabaseUrl=$env:DATABASE_URL
 New-Item -ItemType Directory -Path $temp -Force|Out-Null
 try{
  Copy-Item -LiteralPath (Join-Path $plan.SourceRoot "package.json") -Destination $temp
  Copy-Item -LiteralPath (Join-Path $plan.SourceRoot "package-lock.json") -Destination $temp
  foreach($workspace in @("apps\api","apps\worker","packages\database")){
   $target=Join-Path $temp $workspace;New-Item -ItemType Directory -Path $target -Force|Out-Null
   Copy-Item -LiteralPath (Join-Path (Join-Path $plan.SourceRoot $workspace) "package.json") -Destination $target
   Copy-Item -LiteralPath (Join-Path (Join-Path $plan.SourceRoot $workspace) "dist") -Destination $target -Recurse
  }
  $databaseSource=Join-Path $plan.SourceRoot "packages\database";$databaseTarget=Join-Path $temp "packages\database"
  Copy-Item -LiteralPath (Join-Path $databaseSource "prisma") -Destination $databaseTarget -Recurse
  Copy-Item -LiteralPath (Join-Path $databaseSource "prisma.config.ts") -Destination $databaseTarget
  Push-Location $temp
  try{
   & (Join-Path $plan.InstallRoot "runtime\npm.cmd") "ci" "--omit=dev" "--no-audit" "--no-fund" "--workspace" "@platform/api" "--workspace" "@platform/worker" "--workspace" "@platform/database" "--include-workspace-root=false"
   if($LASTEXITCODE -ne 0){throw "Production dependency installation failed with exit code $LASTEXITCODE."}
   # npm workspace links can be absolute; replace them with physical package copies
   # so the promoted payload remains valid after the temporary staging root is removed.
   $workspaceLinks=@(
    @{Name="@platform/api";Source=(Join-Path $temp "apps\api")},
    @{Name="@platform/worker";Source=(Join-Path $temp "apps\worker")},
    @{Name="@platform/database";Source=(Join-Path $temp "packages\database")}
   )
   $scope=Join-Path $temp "node_modules\@platform"
   New-Item -ItemType Directory -Path $scope -Force|Out-Null
   foreach($workspaceLink in $workspaceLinks){
    $linkPath=Join-Path $scope ($workspaceLink.Name -replace '^@platform/','')
    if(Test-Path -LiteralPath $linkPath){
     $entry=Get-Item -LiteralPath $linkPath -Force
     if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){throw "Expected npm workspace link at $linkPath; refusing to replace an unexpected physical directory."}
     Remove-Item -LiteralPath $linkPath -Force
    }
    New-Item -ItemType Directory -Path $linkPath -Force|Out-Null
    Get-ChildItem -LiteralPath $workspaceLink.Source -Force|Copy-Item -Destination $linkPath -Recurse -Force
   }
   $env:DATABASE_URL="postgresql://runtime-check:runtime-check@127.0.0.1:5432/runtime_check"
   & (Join-Path $plan.InstallRoot "runtime\node.exe") "--input-type=module" "-e" "await import('@platform/database'); await import('fastify'); await import('@node-rs/argon2'); console.log('API/Worker production dependency resolution passed.');"
   if($LASTEXITCODE -ne 0){throw "Production runtime module-resolution smoke test failed."}
  }finally{Pop-Location}
  $promotions=@(
   @{Source=(Join-Path $temp "node_modules");Destination=(Join-Path $plan.InstallRoot "node_modules")},
   @{Source=(Join-Path $temp "apps\api");Destination=(Join-Path $plan.InstallRoot "apps\api")},
   @{Source=(Join-Path $temp "apps\worker");Destination=(Join-Path $plan.InstallRoot "apps\worker")},
   @{Source=(Join-Path $temp "packages\database");Destination=(Join-Path $plan.InstallRoot "packages\database")}
  )
  foreach($item in $promotions){$parent=Split-Path $item.Destination -Parent;New-Item -ItemType Directory -Path $parent -Force|Out-Null;if(Test-Path -LiteralPath $item.Destination){throw "Destination appeared during promotion: $($item.Destination)"};[IO.Directory]::Move($item.Source,$item.Destination);$promoted.Add($item.Destination)}
  [pscustomobject]@{installRoot=$plan.InstallRoot;nodeVersion=$plan.NodeVersion;workspaces=$plan.Workspaces;staged=$true;productionDependencies=$true;installerCreated=$false}|ConvertTo-Json -Depth 4
 }catch{
  foreach($destination in @($promoted.ToArray()|Select-Object -Reverse)){if(Test-Path -LiteralPath $destination){Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue}}
  throw
 }finally{
  if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
  $env:DATABASE_URL=$previousDatabaseUrl
 }
}