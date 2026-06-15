// Web platform helpers keep non-IO builds free from dart:io imports.

bool get isWebPlatform => true;
bool get isWindowsPlatform => false;
bool get isLinuxPlatform => false;
bool get isMacOSPlatform => false;
