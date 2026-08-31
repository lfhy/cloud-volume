// Mobile file-page back navigation bridge. It keeps Android shell routing
// independent from the shared file-manager mutation state.

import 'package:flutter/foundation.dart';

/// Lets the Android shell ask the active file browser to consume Back first.
class MobileFileManagerNavigation extends ChangeNotifier {
  Future<bool> Function()? _onBackRequested;

  void bind(Future<bool> Function() onBackRequested) {
    _onBackRequested = onBackRequested;
  }

  /// Drops the active page callback without relying on tear-off equality.
  void clear() => _onBackRequested = null;

  /// Returns true when a bucket, directory, or recycle-bin view handled Back.
  Future<bool> handleBack() async => await _onBackRequested?.call() ?? false;
}
