# Build the multi-ABI Debug APK for emulator/development use.
param([string]$FlutterRoot = $(if ($env:FLUTTER_ROOT) { $env:FLUTTER_ROOT } else { 'D:\toolchains\flutter' }))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$goRoot = 'D:\toolchains\go\bin'
if ((Test-Path -LiteralPath $goRoot) -and (($env:Path -split ';') -notcontains $goRoot)) { $env:Path = "$goRoot;$env:Path" }
$root = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) { throw "Flutter was not found: $flutter" }
& (Join-Path $PSScriptRoot 'build_android_bridge.ps1') -Abi arm64-v8a
if ($LASTEXITCODE -ne 0) { throw 'Android ARM64 bridge build failed.' }
& (Join-Path $PSScriptRoot 'build_android_bridge.ps1') -Abi x86_64
if ($LASTEXITCODE -ne 0) { throw 'Android x86_64 bridge build failed.' }
Push-Location $root
try { & $flutter build apk --debug --dart-define=APP_VERSION_LABEL=dev; if ($LASTEXITCODE -ne 0) { throw 'Android debug build failed.' } } finally { Pop-Location }
$source = Join-Path $root 'build\app\outputs\flutter-apk\app-debug.apk'
$target = Join-Path (Split-Path -Parent $source) 'cloud-volume-debug.apk'
if (-not (Test-Path -LiteralPath $source)) { throw "APK was not produced: $source" }
Copy-Item -LiteralPath $source -Destination $target -Force
Write-Host "Built debug APK: $target" -ForegroundColor Green
