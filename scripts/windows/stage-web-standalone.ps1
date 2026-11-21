[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$StandaloneDirectory,[Parameter(Mandatory=$true)][string]$InstallRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$source=[IO.Path]::GetFullPath($StandaloneDirectory)
$destination=Join-Path ([IO.Path]::GetFullPath($InstallRoot)) "apps\web\.next\standalone"
if(-not(Test-Path -LiteralPath (Join-Path $source "server.js") -PathType Leaf)){throw "Next.js standalone server.js is missing."}
if(-not(Test-Path -LiteralPath (Join-Path $source "node_modules\next") -PathType Container)){throw "Standalone Next.js dependencies are incomplete."}
New-Item -ItemType Directory -Force -Path $destination|Out-Null
Get-ChildItem -LiteralPath $source -Force|Copy-Item -Destination $destination -Recurse -Force
$staticSource=Join-Path (Split-Path $source -Parent) "static"
if(Test-Path -LiteralPath $staticSource -PathType Container){$staticTarget=Join-Path $destination ".next\static";New-Item -ItemType Directory -Force -Path $staticTarget|Out-Null;Get-ChildItem -LiteralPath $staticSource -Force|Copy-Item -Destination $staticTarget -Recurse -Force}
$publicSource=Join-Path (Split-Path (Split-Path $source -Parent) -Parent) "public"
if(Test-Path -LiteralPath $publicSource -PathType Container){$publicTarget=Join-Path $destination "public";New-Item -ItemType Directory -Force -Path $publicTarget|Out-Null;Get-ChildItem -LiteralPath $publicSource -Force|Copy-Item -Destination $publicTarget -Recurse -Force}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\web\windows\service-entry.cjs") -Destination (Join-Path $destination "service-entry.cjs") -Force
if(-not(Test-Path -LiteralPath (Join-Path $destination "service-entry.cjs") -PathType Leaf)){throw "Web service entry point was not staged."}
Write-Output "Web standalone payload staged at $destination"
