// Conditional directory helpers keep desktop-only filesystem code out of web builds.

export 'default_download_directory_io.dart'
    if (dart.library.html) 'default_download_directory_web.dart';
