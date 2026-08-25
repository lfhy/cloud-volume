# Build the ARM64 Release APK intended for physical Android phones.
# The installed application label is configured separately as “云卷”.
param(
  [string]$FlutterRoot = $(if ($env:FLUTTER_ROOT) { $env:FLUTTER_ROOT } else { 'D:\toolchains\flutter' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'build_android.ps1'
& $buildScript -FlutterRoot $FlutterRoot -SplitPerAbi -OutputName 'cloud-volume-release.apk'
if ($LASTEXITCODE -ne 0) {
  throw "Android real-device APK build failed with exit code $LASTEXITCODE."
}

$apk = Join-Path $repoRoot 'build\app\outputs\flutter-apk\cloud-volume-release-arm64-v8a.apk'
if (-not (Test-Path -LiteralPath $apk)) {
  throw "ARM64 real-device APK was not produced: $apk"
}
Write-Host "Built real-device APK: $apk" -ForegroundColor Green
