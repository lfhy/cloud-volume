// IO platform helpers map dart:io Platform flags to a shared import surface.

import 'dart:io';

bool get isWebPlatform => false;
bool get isWindowsPlatform => Platform.isWindows;
bool get isLinuxPlatform => Platform.isLinux;
bool get isMacOSPlatform => Platform.isMacOS;
