# Builds the Android APK after packaging the Go FFI bridge for both ARM64 and x86_64.
param(
  [string]$FlutterRoot = $(if ($env:FLUTTER_ROOT) { $env:FLUTTER_ROOT } else { Join-Path $HOME 'dev\flutter' }),
  [switch]$Debug,
  [string]$OutputName = $(if ($Debug) { 'cloud-volumn-debug.apk' } else { 'cloud-volumn-release.apk' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) {
  throw "Flutter was not found: $flutter"
}

& (Join-Path $PSScriptRoot 'build_android_bridge.ps1') -Abi arm64-v8a
if ($LASTEXITCODE -ne 0) {
  throw "Android arm64 bridge build failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot 'build_android_bridge.ps1') -Abi x86_64
if ($LASTEXITCODE -ne 0) {
  throw "Android x86_64 bridge build failed with exit code $LASTEXITCODE."
}

Push-Location $repoRoot
try {
  $mode = if ($Debug) { 'debug' } else { 'release' }
  & $flutter build apk "--$mode" --dart-define=APP_VERSION_LABEL=dev
  if ($LASTEXITCODE -ne 0) {
    throw "Android APK build failed with exit code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}

$apk = Join-Path $repoRoot $(if ($Debug) { 'build\app\outputs\flutter-apk\app-debug.apk' } else { 'build\app\outputs\flutter-apk\app-release.apk' })
if (-not (Test-Path -LiteralPath $apk)) {
  throw "Android APK was not produced: $apk"
}
$namedApk = Join-Path (Split-Path -Parent $apk) $OutputName
Copy-Item -LiteralPath $apk -Destination $namedApk -Force
Write-Host "Built Android APK: $apk" -ForegroundColor Green
Write-Host "Named APK: $namedApk" -ForegroundColor Green
