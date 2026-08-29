# Build the ARM64 Release APK for physical Android devices.
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
Push-Location $root
try { & $flutter build apk --release --split-per-abi --dart-define=APP_VERSION_LABEL=dev; if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' } } finally { Pop-Location }
$source = Join-Path $root 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
$target = Join-Path (Split-Path -Parent $source) 'cloud-volume-release-arm64-v8a.apk'
if (-not (Test-Path -LiteralPath $source)) { throw "APK was not produced: $source" }
Copy-Item -LiteralPath $source -Destination $target -Force
Write-Host "Built real-device APK: $target" -ForegroundColor Green
