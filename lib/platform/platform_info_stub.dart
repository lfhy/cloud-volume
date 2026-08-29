// Platform capability helpers isolate conditional imports away from widgets.

bool get isWebPlatform => false;
bool get isWindowsPlatform => false;
bool get isLinuxPlatform => false;
bool get isMacOSPlatform => false;
bool get isAndroidPlatform => false;
bool get isIOSPlatform => false;
bool get isDesktopPlatform => false;

/// Best-effort runtime CPU architecture label used by update asset matching.
String get runtimeCpuArchitecture => '';
