// Mobile settings-page back navigation bridge. Same bind/clear contract as
// MobileFileManagerNavigation: the shell asks the bound handler to consume
// Back; the handler is bound only while a settings detail page is open, so
// consumeBack returning false means the shell falls through to tab history.

import 'package:flutter/foundation.dart';

/// Lets the Android shell ask the active settings detail page to consume Back.
class MobileSettingsNavigation extends ChangeNotifier {
  VoidCallback? _onBackRequested;

  void bind(VoidCallback onBackRequested) {
    _onBackRequested = onBackRequested;
  }

  /// Drops the active page callback without relying on tear-off equality.
  void clear() => _onBackRequested = null;

  /// Returns true when an open settings detail page handled Back by
  /// collapsing back to the settings index.
  bool consumeBack() {
    final handler = _onBackRequested;
    if (handler == null) return false;
    handler();
    return true;
  }
}
