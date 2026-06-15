// Desktop window-control channel keeps custom chrome in Flutter while the
// native runner still owns the actual window state transitions.

import 'package:flutter/services.dart';
import 'package:remote_storage/platform/platform_info.dart';

class WindowControls {
  WindowControls._();

  static const MethodChannel _channel = MethodChannel(
    'remote_storage/window_controls',
  );

  static bool get supported => isWindowsPlatform || isLinuxPlatform;

  static bool get supportsTray => isWindowsPlatform;

  static Future<void> minimize() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('minimize');
  }

  static Future<bool> toggleMaximize() async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>('toggleMaximize') ?? false;
  }

  static Future<bool> isMaximized() async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>('isMaximized') ?? false;
  }

  static Future<void> close() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('close');
  }

  static Future<void> hideToTray() async {
    if (!supportsTray) return;
    await _channel.invokeMethod<void>('hideToTray');
  }

  static Future<void> startDrag() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('startDrag');
  }
}
