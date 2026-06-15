// Conditional file-access service import keeps web builds away from local IO code.

export 'file_access_service_io.dart'
    if (dart.library.html) 'file_access_service_web.dart';
