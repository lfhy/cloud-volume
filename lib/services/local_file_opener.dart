// Conditional local-file opener import keeps web builds free from dart:io.

export 'local_file_opener_io.dart'
    if (dart.library.html) 'local_file_opener_web.dart';
