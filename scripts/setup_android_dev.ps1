# Bootstraps the user-scoped Flutter Android toolchain used by this repository.
param(
  [string]$FlutterRoot = (Join-Path $HOME 'dev\flutter'),
  [string]$FlutterArchive = '',
  [string]$AndroidSdkRoot = (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
  [string]$JavaHome = (Join-Path $HOME 'dev\jdk-17'),
  [switch]$SkipEmulator,
  [switch]$SkipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section {
  param([string]$Message)
  Write-Host ''
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Add-UserPathEntry {
  param([string]$Entry)

  if (-not (Test-Path -LiteralPath $Entry)) {
    return
  }
  $resolved = (Resolve-Path -LiteralPath $Entry).Path.TrimEnd('\')
  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  $items = if ($current) {
    @($current.Split(';') | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ })
  } else {
    @()
  }
  if (-not ($items | Where-Object { [string]::Equals($_, $resolved, [StringComparison]::OrdinalIgnoreCase) })) {
    [Environment]::SetEnvironmentVariable('Path', (@($items) + $resolved -join ';'), 'User')
    Write-Host "Added to user PATH: $resolved"
  }
  if ($env:Path -notlike "*$resolved*") {
    $env:Path = "$resolved;$env:Path"
  }
}

function Ensure-GitSafeDirectory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
    return
  }
  $resolved = (Resolve-Path -LiteralPath $Path).Path.Replace('\', '/')
  $existing = @(& git config --global --get-all safe.directory 2>$null)
  if ($existing | Where-Object { [string]::Equals($_.TrimEnd('/'), $resolved.TrimEnd('/'), [StringComparison]::OrdinalIgnoreCase) }) {
    return
  }
  Write-Host "Adding Flutter to Git safe.directory: $resolved"
  & git config --global --add safe.directory $resolved
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not add Flutter to Git safe.directory.'
  }
}

function Save-Download {
  param([string]$Url, [string]$Destination)

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
  $lastError = $null
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Write-Host "Downloading $Url (attempt $attempt/3)"
      Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 45
      if ((Get-Item -LiteralPath $Destination).Length -gt 0) {
        return
      }
      $lastError = 'downloaded file is empty'
    } catch {
      $lastError = $_.Exception.Message
      Start-Sleep -Seconds $attempt
    }
  }
  throw "Failed to download $Url. $lastError"
}

function Install-ZipDirectory {
  param([string]$Url, [string]$Destination, [string]$ExpectedRelativePath)

  if (Test-Path -LiteralPath (Join-Path $Destination $ExpectedRelativePath)) {
    Write-Host "Using existing $Destination"
    return
  }
  $tempZip = Join-Path $env:TEMP ([guid]::NewGuid().ToString() + '.zip')
  $tempDirectory = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
  $installed = $false
  try {
    Save-Download -Url $Url -Destination $tempZip
    Expand-Archive -LiteralPath $tempZip -DestinationPath $tempDirectory -Force
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    if (Test-Path -LiteralPath $Destination) {
      throw "Refusing to replace existing incomplete installation: $Destination"
    }
    $children = @(Get-ChildItem -LiteralPath $tempDirectory -Force)
    if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
      Move-Item -LiteralPath $children[0].FullName -Destination $Destination
    } else {
      New-Item -ItemType Directory -Force -Path $Destination | Out-Null
      Get-ChildItem -LiteralPath $tempDirectory -Force | Move-Item -Destination $Destination
    }
  } finally {
    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Install-LocalZipDirectory {
  param([string]$Archive, [string]$Destination, [string]$ExpectedRelativePath)

  if (Test-Path -LiteralPath (Join-Path $Destination $ExpectedRelativePath)) {
    Write-Host "Using existing $Destination"
    return
  }
  if (-not (Test-Path -LiteralPath $Archive)) {
    throw "Flutter archive was not found: $Archive"
  }
  if ((Get-Item -LiteralPath $Archive).Length -le 0) {
    throw "Flutter archive is empty: $Archive"
  }

  $tempDirectory = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
  $installed = $false
  try {
    Write-Host "Using local Flutter archive: $Archive"
    New-Item -ItemType Directory -Force -Path $tempDirectory | Out-Null
    # Expand-Archive mishandles the metadata directories bundled by Flutter 3.47.
    & tar.exe -xf $Archive -C $tempDirectory
    if ($LASTEXITCODE -ne 0) {
      throw "Could not extract local Flutter archive (tar exit code $LASTEXITCODE): $Archive"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    if (Test-Path -LiteralPath $Destination) {
      throw "Refusing to replace existing incomplete installation: $Destination"
    }
    $children = @(Get-ChildItem -LiteralPath $tempDirectory -Force)
    if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
      Move-Item -LiteralPath $children[0].FullName -Destination $Destination
    } else {
      New-Item -ItemType Directory -Force -Path $Destination | Out-Null
      Get-ChildItem -LiteralPath $tempDirectory -Force | Move-Item -Destination $Destination
    }
    $installed = $true
  } finally {
    # The extracted Flutter tree is very large; avoid a second recursive delete
    # after tar has already moved it into place. Temp files are safe to inspect
    # or remove later, while failed extractions still get cleaned up.
    if (-not $installed) {
      Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Get-FlutterArchiveUrl {
  $manifest = Invoke-RestMethod -Uri 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json' -TimeoutSec 45
  $release = $manifest.releases | Where-Object { $_.hash -eq $manifest.current_release.stable } | Select-Object -First 1
  if (-not $release -or -not $release.archive) {
    throw 'Could not resolve the current Flutter stable Windows archive.'
  }
  return "https://storage.googleapis.com/flutter_infra_release/releases/$($release.archive)"
}

function Get-AndroidCommandLineToolsUrl {
  [xml]$repository = Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/repository2-1.xml' -UseBasicParsing -TimeoutSec 45
  $node = $repository.SelectSingleNode("//*[local-name()='remotePackage' and @path='cmdline-tools;latest']//*[local-name()='archive'][*[local-name()='host-os' and text()='windows']]/*[local-name()='complete']/*[local-name()='url']")
  if (-not $node -or -not $node.InnerText) {
    throw 'Could not resolve the Android command-line tools archive.'
  }
  return "https://dl.google.com/android/repository/$($node.InnerText)"
}

function Invoke-SdkManager {
  param([string]$SdkManager, [string[]]$Arguments)

  & $SdkManager "--sdk_root=$AndroidSdkRoot" @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "sdkmanager $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
  }
}

Write-Section 'JDK 17'
Install-ZipDirectory -Url 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse' -Destination $JavaHome -ExpectedRelativePath 'bin\java.exe'
$env:JAVA_HOME = $JavaHome
[Environment]::SetEnvironmentVariable('JAVA_HOME', $JavaHome, 'User')
Add-UserPathEntry (Join-Path $JavaHome 'bin')

Write-Section 'Flutter stable'
$defaultFlutterArchive = Join-Path (Split-Path -Parent $PSScriptRoot) 'flutter_windows_3.47.0-stable.zip'
if (-not $FlutterArchive) {
  $FlutterArchive = $defaultFlutterArchive
}
if (Test-Path -LiteralPath $FlutterArchive) {
  Install-LocalZipDirectory -Archive $FlutterArchive -Destination $FlutterRoot -ExpectedRelativePath 'bin\flutter.bat'
} else {
  Write-Host "Local Flutter archive not found; falling back to the online stable release." -ForegroundColor Yellow
  Install-ZipDirectory -Url (Get-FlutterArchiveUrl) -Destination $FlutterRoot -ExpectedRelativePath 'bin\flutter.bat'
}
Add-UserPathEntry (Join-Path $FlutterRoot 'bin')
Ensure-GitSafeDirectory -Path $FlutterRoot
[Environment]::SetEnvironmentVariable('FLUTTER_ROOT', $FlutterRoot, 'User')
$env:FLUTTER_ROOT = $FlutterRoot

Write-Section 'Android SDK command-line tools'
$commandLineTools = Join-Path $AndroidSdkRoot 'cmdline-tools\latest'
if (-not (Test-Path -LiteralPath (Join-Path $commandLineTools 'bin\sdkmanager.bat'))) {
  $tempZip = Join-Path $env:TEMP ([guid]::NewGuid().ToString() + '.zip')
  $tempDirectory = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
  try {
    Save-Download -Url (Get-AndroidCommandLineToolsUrl) -Destination $tempZip
    Expand-Archive -LiteralPath $tempZip -DestinationPath $tempDirectory -Force
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $commandLineTools) | Out-Null
    if (Test-Path -LiteralPath $commandLineTools) {
      throw "Refusing to replace existing incomplete Android command-line tools: $commandLineTools"
    }
    Move-Item -LiteralPath (Join-Path $tempDirectory 'cmdline-tools') -Destination $commandLineTools
  } finally {
    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
$env:ANDROID_SDK_ROOT = $AndroidSdkRoot
$env:ANDROID_HOME = $AndroidSdkRoot
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $AndroidSdkRoot, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $AndroidSdkRoot, 'User')
Add-UserPathEntry (Join-Path $commandLineTools 'bin')
Add-UserPathEntry (Join-Path $AndroidSdkRoot 'platform-tools')
Add-UserPathEntry (Join-Path $AndroidSdkRoot 'emulator')
$sdkManager = Join-Path $commandLineTools 'bin\sdkmanager.bat'

Write-Section 'Android SDK packages and licenses'
$licenseAnswers = Join-Path $env:TEMP ([guid]::NewGuid().ToString() + '.txt')
try {
  Set-Content -LiteralPath $licenseAnswers -Value (@('y') * 200)
  Get-Content -LiteralPath $licenseAnswers | & $sdkManager "--sdk_root=$AndroidSdkRoot" --licenses
  if ($LASTEXITCODE -ne 0) {
    throw "sdkmanager --licenses failed with exit code $LASTEXITCODE."
  }
} finally {
  Remove-Item -LiteralPath $licenseAnswers -Force -ErrorAction SilentlyContinue
}
# The Go FFI bridge is cross-compiled with this pinned NDK by build_android_bridge.ps1.
Invoke-SdkManager -SdkManager $sdkManager -Arguments @('platform-tools', 'platforms;android-36', 'build-tools;36.0.0', 'ndk;28.2.13676358')
if (-not $SkipEmulator) {
  Invoke-SdkManager -SdkManager $sdkManager -Arguments @('emulator', 'system-images;android-36;google_apis;x86_64')
}

Write-Section 'Flutter Android configuration'
$flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
& $flutter config --android-sdk $AndroidSdkRoot
if ($LASTEXITCODE -ne 0) {
  throw "flutter config failed with exit code $LASTEXITCODE."
}
& $flutter doctor -v
if ($LASTEXITCODE -ne 0) {
  throw "flutter doctor failed with exit code $LASTEXITCODE."
}

if (-not $SkipValidation) {
  Write-Section 'Project dependency validation'
  Push-Location (Split-Path -Parent $PSScriptRoot)
  try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE." }
    & $flutter test
    if ($LASTEXITCODE -ne 0) { throw "flutter test failed with exit code $LASTEXITCODE." }
  } finally {
    Pop-Location
  }
}

Write-Host ''
Write-Host 'Android toolchain setup completed. Open a new PowerShell window before using flutter, adb, or java interactively.' -ForegroundColor Green
