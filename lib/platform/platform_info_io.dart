// IO platform helpers map dart:io Platform flags to a shared import surface.

import 'dart:io';

bool get isWebPlatform => false;
bool get isWindowsPlatform => Platform.isWindows;
bool get isLinuxPlatform => Platform.isLinux;
bool get isMacOSPlatform => Platform.isMacOS;
bool get isAndroidPlatform => Platform.isAndroid;
bool get isIOSPlatform => Platform.isIOS;
bool get isDesktopPlatform =>
    isWindowsPlatform || isLinuxPlatform || isMacOSPlatform;

/// Best-effort CPU architecture of the running Dart/Flutter process.
String get runtimeCpuArchitecture {
  final version = Platform.version.toLowerCase();
  if (version.contains('arm64') || version.contains('aarch64')) {
    return 'arm64';
  }
  if (version.contains('x64') ||
      version.contains('x86_64') ||
      version.contains('amd64')) {
    return 'amd64';
  }
  return '';
}
