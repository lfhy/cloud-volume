# Builds the Go bridge that the Android Flutter runner loads through FFI.
param(
  [string]$AndroidSdkRoot = $(
    if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
  ),
  [string]$NdkVersion = '28.2.13676358',
  [int]$ApiLevel = 24,
  [ValidateSet('arm64-v8a', 'x86_64')]
  [string]$Abi = 'arm64-v8a'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$ndkRoot = Join-Path $AndroidSdkRoot "ndk\$NdkVersion"
$toolchainBin = Join-Path $ndkRoot 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$compiler = switch ($Abi) {
  'arm64-v8a' { Join-Path $toolchainBin "aarch64-linux-android$ApiLevel-clang.cmd" }
  'x86_64' { Join-Path $toolchainBin "x86_64-linux-android$ApiLevel-clang.cmd" }
}
$outputDirectory = Join-Path $repoRoot "android\app\src\main\jniLibs\$Abi"
$library = Join-Path $outputDirectory 'libremote_storage_bridge.so'
$header = Join-Path $outputDirectory 'libremote_storage_bridge.h'

if (-not (Test-Path -LiteralPath $compiler)) {
  throw "Android NDK $NdkVersion is required. Install it with: sdkmanager `"ndk;$NdkVersion`""
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$env:GOOS = 'android'
$goArch = switch ($Abi) {
  'arm64-v8a' { 'arm64' }
  'x86_64' { 'amd64' }
}
$env:GOARCH = $goArch
$env:CGO_ENABLED = '1'
$env:CC = $compiler
$env:GOPROXY = 'https://goproxy.cn,direct'
$env:GOSUMDB = 'sum.golang.google.cn'

Push-Location $repoRoot
try {
  & go build -buildmode=c-shared -ldflags "-X main.buildArch=$goArch" -o $library ./bridge
  if ($LASTEXITCODE -ne 0) {
    throw "Android bridge build failed with exit code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}

# The C header is only an intermediate of Go's c-shared build, not an APK asset.
Remove-Item -LiteralPath $header -Force -ErrorAction SilentlyContinue
Write-Host "Built Android bridge: $library" -ForegroundColor Green
