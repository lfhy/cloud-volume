import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/sidebar_item.dart';

/// Tracks which bottom-bar tabs currently hold an active selection (Android
/// two-state selection model). The shell hides the bottom navigation bar
/// while the *visible* tab reports an active selection, so the selection
/// bottom bar replaces it edge to edge (Baidu-style). Hidden IndexedStack
/// children may keep stale reports; the shell always combines the report with
/// the current tab, so only the visible tab's state matters.
///
/// Pages call [report] from their build methods; notifications are deferred
/// to a microtask so a page can report without marking the shell's listeners
/// dirty mid-frame.
class MobileSelectionActivity extends ChangeNotifier {
  MobileSelectionActivity._();

  static final MobileSelectionActivity instance = MobileSelectionActivity._();

  final Set<SidebarItem> _activeTabs = <SidebarItem>{};
  bool _notifyScheduled = false;

  bool isActive(SidebarItem item) => _activeTabs.contains(item);

  /// Reports [active] for [item]; notifies listeners (deferred) only when the
  /// value actually changes.
  void report(SidebarItem item, bool active) {
    final changed = active ? _activeTabs.add(item) : _activeTabs.remove(item);
    if (changed) _scheduleNotify();
  }

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (hasListeners) notifyListeners();
    });
  }
}
