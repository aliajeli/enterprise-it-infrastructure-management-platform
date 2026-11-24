# Stages a separate pinned Prisma CLI and schema engine for future offline
# deployment. It does not execute migrations or enable database mutation.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$InstallRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-MigrationToolStagePlan {
 [CmdletBinding()]
 param([string]$SourceRoot,[string]$InstallRoot)
 $source=[IO.Path]::GetFullPath($SourceRoot)
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
 $pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)).TrimEnd([IO.Path]::DirectorySeparatorChar)
 if(-not $root.StartsWith(($pf+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'Install root must be beneath Program Files.'}
 $parts=$root.Substring($pf.Length+1).Split([IO.Path]::DirectorySeparatorChar)
 if($parts.Length -ne 2 -or $parts[0] -ne 'EnterpriseIT' -or $parts[1] -notmatch '^\d+\.\d+\.\d+$'){throw 'Install root must be Program Files\EnterpriseIT\<major.minor.patch>.'}
 foreach($relative in @('package.json','package-lock.json','packages\database\package.json','scripts\windows\migration-prisma.config.ts')){
  if(-not(Test-Path -LiteralPath (Join-Path $source $relative) -PathType Leaf)){throw "Migration tooling source is missing: $relative"}
 }
 $db=Get-Content -LiteralPath (Join-Path $source 'packages\database\package.json') -Raw|ConvertFrom-Json
 if([string]$db.devDependencies.prisma -cne '7.10.1'){throw 'Migration tool requires pinned Prisma 7.10.1.'}
 $node=Join-Path $root 'runtime\node.exe';$npm=Join-Path $root 'runtime\npm.cmd'
 if(-not(Test-Path -LiteralPath $node -PathType Leaf) -or -not(Test-Path -LiteralPath $npm -PathType Leaf)){throw 'Bundled Node and npm must be staged first.'}
 $version=(& $node --version 2>&1|Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $version -notmatch '^v26\.'){throw 'Migration tool staging requires bundled Node 26.'}
 $destination=Join-Path $root 'migration-tool'
 if(Test-Path -LiteralPath $destination){throw 'Immutable migration tool destination exists; refusing overwrite.'}
 [pscustomobject]@{SourceRoot=$source;InstallRoot=$root;Destination=$destination;PrismaVersion='7.10.1';NodeVersion=$version;Immutable=$true}
}
if($MyInvocation.InvocationName -ne '.'){
 $plan=Get-MigrationToolStagePlan -SourceRoot $SourceRoot -InstallRoot $InstallRoot
 if($WhatIfPreference){[pscustomobject]@{destination=$plan.Destination;prismaVersion=$plan.PrismaVersion;dryRun=$true;databaseMutated=$false}|ConvertTo-Json;return}
 if(-not $PSCmdlet.ShouldProcess($plan.Destination,'Stage pinned isolated Prisma migration tooling')){return}
 $temp=Join-Path ([IO.Path]::GetTempPath()) ('enterpriseit-migration-tool-'+[guid]::NewGuid().ToString('N'))
 $promoted=$false
 try{
  New-Item -ItemType Directory -Path (Join-Path $temp 'packages\database') -ErrorAction Stop|Out-Null
  foreach($file in @('package.json','package-lock.json')){Copy-Item -LiteralPath (Join-Path $plan.SourceRoot $file) -Destination $temp}
  Copy-Item -LiteralPath (Join-Path $plan.SourceRoot 'packages\database\package.json') -Destination (Join-Path $temp 'packages\database\package.json')
  Push-Location $temp
  try{
   & (Join-Path $plan.InstallRoot 'runtime\npm.cmd') 'ci' '--include=dev' '--no-audit' '--no-fund' '--workspace' '@platform/database' '--include-workspace-root=false'
   if($LASTEXITCODE -ne 0){throw 'Migration tool dependency installation failed.'}
  }finally{Pop-Location}
  # The database workspace link points to the disposable build tree. It is not
  # a tool dependency; remove it rather than ship a reparse point or stale link.
  $workspaceLink=Join-Path $temp 'node_modules\@platform\database'
  if(Test-Path -LiteralPath $workspaceLink){Remove-Item -LiteralPath $workspaceLink -Force -Recurse -ErrorAction Stop}
  $tool=Join-Path $temp 'tool';New-Item -ItemType Directory -Path $tool -ErrorAction Stop|Out-Null
  [IO.Directory]::Move((Join-Path $temp 'node_modules'),(Join-Path $tool 'node_modules'))
  Copy-Item -LiteralPath (Join-Path $plan.SourceRoot 'scripts\windows\migration-prisma.config.ts') -Destination (Join-Path $tool 'prisma.config.ts')
  foreach($relative in @('prisma.config.ts','node_modules\prisma\package.json','node_modules\prisma\build\index.js','node_modules\@prisma\engines\schema-engine-windows.exe')){
   if(-not(Test-Path -LiteralPath (Join-Path $tool $relative) -PathType Leaf)){throw "Migration tooling is incomplete: $relative"}
  }
  $prisma=Get-Content -LiteralPath (Join-Path $tool 'node_modules\prisma\package.json') -Raw|ConvertFrom-Json
  if([string]$prisma.version -cne $plan.PrismaVersion){throw 'Staged Prisma version differs from the pinned version.'}
  if(Test-Path -LiteralPath $plan.Destination){throw 'Migration tool destination appeared during staging.'}
  [IO.Directory]::Move($tool,$plan.Destination);$promoted=$true
  [pscustomobject]@{destination=$plan.Destination;prismaVersion=$plan.PrismaVersion;staged=$true;databaseMutated=$false;installerCreated=$false}|ConvertTo-Json
 }finally{
  if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
 }
}
