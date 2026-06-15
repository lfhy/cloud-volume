// Shared bootstrap entry point selects the right per-platform initialization.

export 'platform_bootstrap_io.dart'
    if (dart.library.html) 'platform_bootstrap_web.dart';
