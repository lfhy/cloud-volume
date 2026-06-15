// Detached file preview window gives image previews more room than a modal.

import 'package:flutter/material.dart';
import 'package:remote_storage/app/app_brand.dart';
import 'package:remote_storage/models/file_preview_window_args.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/widgets/file_preview_pane.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

class FilePreviewWindowApp extends StatelessWidget {
  const FilePreviewWindowApp({super.key, required this.args});

  final FilePreviewWindowArgs args;

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: '$appBrandName - ${args.title}',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: buildAppTheme(AccentPreset.blue),
      home: FilePreviewWindow(args: args),
    );
  }
}

class FilePreviewWindow extends StatelessWidget {
  const FilePreviewWindow({super.key, required this.args});

  final FilePreviewWindowArgs args;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Column(
        children: [
          _PreviewWindowTitleBar(title: args.title),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(color: theme.colorScheme.secondary),
              child: FilePreviewPane(
                kind: args.kind,
                localPath: args.localPath,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewWindowTitleBar extends StatelessWidget {
  const _PreviewWindowTitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return DragToMoveArea(
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.background,
          border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => windowManager.close(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
