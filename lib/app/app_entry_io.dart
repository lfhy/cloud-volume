// Desktop entry chooses between the main app and detached preview sub-windows.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/app/file_preview_window_app.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/models/file_preview_window_args.dart';
import 'package:window_manager/window_manager.dart';

Future<void> runRemoteStorageEntry(List<String> args) async {
  final controller = await WindowController.fromCurrentEngine();
  final arguments = controller.arguments;
  await windowManager.ensureInitialized();

  if (FilePreviewWindowArgs.matches(arguments)) {
    final previewArgs = FilePreviewWindowArgs.fromArguments(arguments);
    await _configurePreviewWindow(previewArgs.title);
    runApp(FilePreviewWindowApp(args: previewArgs));
    return;
  }

  runApp(const RemoteStorageApp());
}

Future<void> _configurePreviewWindow(String title) async {
  const options = WindowOptions(
    size: Size(1040, 760),
    minimumSize: Size(720, 520),
    center: true,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setTitle(title);
    await windowManager.show();
    await windowManager.focus();
  });
}
