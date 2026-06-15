// Shared platform flags use conditional imports so web builds avoid dart:io.

export 'platform_info_stub.dart'
    if (dart.library.io) 'platform_info_io.dart'
    if (dart.library.html) 'platform_info_web.dart';
