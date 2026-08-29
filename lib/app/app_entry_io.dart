// Desktop entry chooses between the main app and detached preview sub-windows.

import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/app/account_editor_window_app.dart';
import 'package:remote_storage/app/app_brand.dart';
import 'package:remote_storage/app/desktop_modal_window_config.dart';
import 'package:remote_storage/app/file_preview_window_app.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/app/remote_directory_picker_window_app.dart';
import 'package:remote_storage/app/sync_editor_window_app.dart';
import 'package:remote_storage/models/account_editor_window_args.dart';
import 'package:remote_storage/models/remote_directory_picker_window_args.dart';
import 'package:remote_storage/models/file_preview_window_args.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/sync_editor_window_args.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:window_manager/window_manager.dart';

Future<void> runRemoteStorageEntry(List<String> args) async {
  if (Platform.isAndroid || Platform.isIOS) {
    runApp(const RemoteStorageApp());
    return;
  }
  final controller = await WindowController.fromCurrentEngine();
  final arguments = controller.arguments;
  await windowManager.ensureInitialized();

  if (FilePreviewWindowArgs.matches(arguments)) {
    final previewArgs = FilePreviewWindowArgs.fromArguments(arguments);
    await _configurePreviewWindow(previewArgs.title);
    runApp(FilePreviewWindowApp(args: previewArgs));
    return;
  }

  if (AccountEditorWindowArgs.matches(arguments)) {
    final editorArgs = AccountEditorWindowArgs.fromArguments(arguments);
    await DesktopWindowMethodHost.ensureInstalled();
    await configureDesktopModalSubWindow(
      title: editorArgs.editing ? '编辑账号' : '新增账号',
      // Initial guess only; CloudStorageAccountDialog measures content and
      // calls fitModalSubWindowToContentSize to remove empty space / scroll.
      size: _accountEditorWindowSize(editorArgs),
      minimumSize: const Size(400, 280),
      creatorFrameLeft: editorArgs.creatorFrameLeft,
      creatorFrameTop: editorArgs.creatorFrameTop,
      creatorFrameWidth: editorArgs.creatorFrameWidth,
      creatorFrameHeight: editorArgs.creatorFrameHeight,
      creatorWindowId: editorArgs.creatorWindowId,
    );
    runApp(AccountEditorWindowApp(args: editorArgs));
    return;
  }

  if (SyncEditorWindowArgs.matches(arguments)) {
    final editorArgs = SyncEditorWindowArgs.fromArguments(arguments);
    await DesktopWindowMethodHost.ensureInstalled();
    await configureDesktopModalSubWindow(
      title: editorArgs.initialProfile != null ? '编辑同步配置' : '新建同步配置',
      size: const Size(600, 480),
      minimumSize: const Size(520, 400),
      creatorFrameLeft: editorArgs.creatorFrameLeft,
      creatorFrameTop: editorArgs.creatorFrameTop,
      creatorFrameWidth: editorArgs.creatorFrameWidth,
      creatorFrameHeight: editorArgs.creatorFrameHeight,
      creatorWindowId: editorArgs.creatorWindowId,
    );
    runApp(SyncEditorWindowApp(args: editorArgs));
    return;
  }

  if (RemoteDirectoryPickerWindowArgs.matches(arguments)) {
    final pickerArgs = RemoteDirectoryPickerWindowArgs.fromArguments(arguments);
    await DesktopWindowMethodHost.ensureInstalled();
    await configureDesktopModalSubWindow(
      title: '选择远端目录',
      size: const Size(640, 560),
      minimumSize: const Size(480, 400),
      anchorFrameLeft: pickerArgs.anchorFrameLeft,
      anchorFrameTop: pickerArgs.anchorFrameTop,
      anchorFrameWidth: pickerArgs.anchorFrameWidth,
      anchorFrameHeight: pickerArgs.anchorFrameHeight,
      creatorFrameLeft: pickerArgs.creatorFrameLeft,
      creatorFrameTop: pickerArgs.creatorFrameTop,
      creatorFrameWidth: pickerArgs.creatorFrameWidth,
      creatorFrameHeight: pickerArgs.creatorFrameHeight,
      creatorWindowId: pickerArgs.creatorWindowId,
    );
    runApp(RemoteDirectoryPickerWindowApp(args: pickerArgs));
    return;
  }

  if (isWindowsPlatform) {
    await _prepareMainWindow();
  }
  runApp(const RemoteStorageApp());
  if (isWindowsPlatform) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

// Configure hidden native chrome before the first visible main-window frame.
Future<void> _prepareMainWindow() async {
  const options = WindowOptions(
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(options);
  await windowManager.setTitle(appBrandName);
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

/// Seed size before the first content measure. Prefer slightly compact for
/// new-account step 0; edit mode seeds by protocol. Final size is content-fit.
Size _accountEditorWindowSize(AccountEditorWindowArgs args) {
  // 480 content + 48 horizontal padding from DesktopModalSubWindowApp.
  // Seed a bit tall so first-frame buttons are not clipped before measure.
  if (!args.editing) return const Size(640, 360);
  final storageType = args.initialConfig?.storageType;
  return switch (storageType) {
    StorageType.baiduPan => const Size(640, 480),
    StorageType.webdav => const Size(640, 520),
    _ => const Size(640, 560),
  };
}
