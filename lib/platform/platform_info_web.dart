// Web platform helpers keep non-IO builds free from dart:io imports.

bool get isWebPlatform => true;
bool get isWindowsPlatform => false;
bool get isLinuxPlatform => false;
bool get isMacOSPlatform => false;
bool get isAndroidPlatform => false;
bool get isIOSPlatform => false;
bool get isDesktopPlatform => false;

/// Browsers do not expose a reliable install target architecture here.
String get runtimeCpuArchitecture => '';
