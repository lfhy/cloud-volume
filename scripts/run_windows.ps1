# Windows local startup helper: resolves a usable Flutter binary and MinGW
# toolchain, builds the Go bridge with CGO enabled, then launches Flutter.
param(
  [string]$FlutterPath,
  [string]$BridgeCc,
  [string]$BridgeCxx,
  [switch]$Build,
  [switch]$SkipPubGet,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($arg in $ExtraArgs) {
  switch ($arg) {
    '--build' {
      $Build = $true
      continue
    }
    '--skip-pub-get' {
      $SkipPubGet = $true
      continue
    }
    default {
      throw "Unknown argument: $arg"
    }
  }
}

function Add-NoProxyEntry {
  param(
    [string]$CurrentValue,
    [string]$Entry
  )

  $items = @()
  if ($CurrentValue) {
    $items = $CurrentValue.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  }
  if ($items -contains $Entry) {
    return ($items -join ',')
  }
  return (@($items) + $Entry) -join ','
}

function Resolve-Executable {
  param(
    [string]$Name,
    [string[]]$Candidates
  )

  if ($Name -and (Test-Path -LiteralPath $Name)) {
    return (Resolve-Path -LiteralPath $Name).Path
  }

  if ($Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
      return $command.Source
    }
  }

  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  return $null
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$bridgeDir = Join-Path $repoRoot 'bin/bridge'
$bridgeDll = Join-Path $bridgeDir 'remote_storage_bridge.dll'
$flutterCandidates = @()
if ($env:FLUTTER_ROOT) {
  $flutterCandidates += (Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat')
}
$flutterCandidates += @(
  (Join-Path $HOME 'dev/flutter/bin/flutter.bat'),
  'C:\src\flutter\bin\flutter.bat'
)
$flutter = Resolve-Executable -Name $FlutterPath -Candidates $flutterCandidates
if (-not $flutter) {
  throw 'Could not find flutter. Pass -FlutterPath or set FLUTTER_ROOT.'
}

$gcc = Resolve-Executable -Name $BridgeCc -Candidates @(
  $env:BRIDGE_CC,
  'C:\msys64\ucrt64\bin\gcc.exe',
  'C:\msys64\mingw64\bin\gcc.exe',
  'C:\msys64\clang64\bin\gcc.exe'
)
if (-not $gcc) {
  throw 'Could not find gcc. Install the MSYS2 UCRT64 toolchain or pass -BridgeCc.'
}

$gxx = Resolve-Executable -Name $BridgeCxx -Candidates @(
  $env:BRIDGE_CXX,
  'C:\msys64\ucrt64\bin\g++.exe',
  'C:\msys64\mingw64\bin\g++.exe',
  'C:\msys64\clang64\bin\g++.exe'
)
if (-not $gxx) {
  throw 'Could not find g++. Install the MSYS2 UCRT64 toolchain or pass -BridgeCxx.'
}

$env:CGO_ENABLED = '1'
$env:BRIDGE_CC = $gcc
$env:BRIDGE_CXX = $gxx
$env:CC = (Split-Path -Leaf $gcc)
$env:CXX = (Split-Path -Leaf $gxx)
$env:PATH = "$(Split-Path -Parent $gcc);$env:PATH"

if ($env:HTTP_PROXY -or $env:HTTPS_PROXY -or $env:ALL_PROXY) {
  $noProxy = $env:NO_PROXY
  $noProxy = Add-NoProxyEntry -CurrentValue $noProxy -Entry '127.0.0.1'
  $noProxy = Add-NoProxyEntry -CurrentValue $noProxy -Entry 'localhost'
  $env:NO_PROXY = $noProxy
  $env:no_proxy = $noProxy
  Write-Host "Using NO_PROXY=$noProxy for local Flutter VM service connections."
}

Push-Location $repoRoot
try {
  if ($Build) {
    Write-Host 'run_windows.ps1 mode: build'
  } else {
    Write-Host 'run_windows.ps1 mode: run'
  }
  & $flutter config --enable-windows-desktop
  if (-not $SkipPubGet) {
    & $flutter pub get
  }

  New-Item -ItemType Directory -Force -Path $bridgeDir | Out-Null
  & go build -buildmode=c-shared -o $bridgeDll ./bridge

  if ($Build) {
    & $flutter build windows --dart-define APP_VERSION_LABEL=dev
  } else {
    & $flutter run -d windows --dart-define APP_VERSION_LABEL=dev
  }
} finally {
  Pop-Location
}
