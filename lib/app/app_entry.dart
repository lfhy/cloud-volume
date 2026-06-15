// App entry delegates desktop-only multi-window startup behind conditional code.

export 'app_entry_io.dart' if (dart.library.html) 'app_entry_web.dart';
