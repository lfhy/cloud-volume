// Conditional local image widget keeps web builds away from dart:io.

export 'local_preview_image_io.dart'
    if (dart.library.html) 'local_preview_image_web.dart';
