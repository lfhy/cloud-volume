// Conditional preview-window service keeps browser builds away from desktop APIs.

export 'file_preview_window_service_io.dart'
    if (dart.library.html) 'file_preview_window_service_web.dart';
