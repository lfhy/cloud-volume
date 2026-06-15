// Conditional file-transfer import keeps web builds away from local file APIs.

export 'desktop_file_transfer_service_io.dart'
    if (dart.library.html) 'desktop_file_transfer_service_web.dart';
