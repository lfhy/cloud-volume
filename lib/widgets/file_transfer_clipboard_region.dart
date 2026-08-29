// File transfer region wires native drops and copy/paste shortcuts into a child surface.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remote_storage/services/desktop_file_transfer_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class FileTransferClipboardRegion extends StatefulWidget {
  const FileTransferClipboardRegion({
    super.key,
    required this.enabled,
    this.acceptsLocalFiles = true,
    required this.onPasteLocalFiles,
    required this.onCopySelection,
    required this.child,
  });

  final bool enabled;
  final bool acceptsLocalFiles;
  final ValueChanged<List<String>> onPasteLocalFiles;
  final VoidCallback onCopySelection;
  final Widget child;

  @override
  State<FileTransferClipboardRegion> createState() =>
      _FileTransferClipboardRegionState();
}

class _FileTransferClipboardRegionState
    extends State<FileTransferClipboardRegion> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'file-transfer-region');
  bool _dropActive = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return widget.child;
    }
    final theme = ShadTheme.of(context);
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _PasteFilesIntent(),
          SingleActivator(LogicalKeyboardKey.keyV, meta: true):
              _PasteFilesIntent(),
          SingleActivator(LogicalKeyboardKey.keyC, control: true):
              _CopyFilesIntent(),
          SingleActivator(LogicalKeyboardKey.keyC, meta: true):
              _CopyFilesIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _PasteFilesIntent: CallbackAction<_PasteFilesIntent>(
              // Paste only needs the region active (bucket loaded, not trash/loading).
              // Directory write-ability is enforced later in onPasteLocalFiles, so a
              // WebDAV permission check still in flight won't silently swallow Cmd+V.
              onInvoke: (_) {
                if (widget.enabled) {
                  unawaited(_pasteLocalFiles());
                }
                return null;
              },
            ),
            _CopyFilesIntent: CallbackAction<_CopyFilesIntent>(
              onInvoke: (_) {
                if (widget.enabled) {
                  widget.onCopySelection();
                }
                return null;
              },
            ),
          },
          child: DropRegion(
            formats: const <DataFormat>[Formats.fileUri],
            hitTestBehavior: HitTestBehavior.opaque,
            onDropOver: _onDropOver,
            onDropEnter: (_) {
              if (_acceptsLocalFiles) {
                setState(() => _dropActive = true);
              }
            },
            onDropLeave: (_) => setState(() => _dropActive = false),
            onDropEnded: (_) => setState(() => _dropActive = false),
            onPerformDrop: _performDrop,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _focusNode.requestFocus(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  if (_dropActive) _DropOverlay(theme: theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  DropOperation _onDropOver(DropOverEvent event) {
    if (!_acceptsLocalFiles) {
      return DropOperation.none;
    }
    final acceptsFile = event.session.items.any(
      (item) => item.canProvide(Formats.fileUri),
    );
    return acceptsFile ? DropOperation.copy : DropOperation.none;
  }

  Future<void> _performDrop(PerformDropEvent event) async {
    setState(() => _dropActive = false);
    if (!_acceptsLocalFiles) {
      return;
    }
    final paths = await DesktopFileTransferService.instance
        .localFilePathsFromDrop(event);
    if (paths.isNotEmpty) {
      widget.onPasteLocalFiles(paths);
    }
  }

  Future<void> _pasteLocalFiles() async {
    final paths = await DesktopFileTransferService.instance
        .localFilePathsFromClipboard();
    if (paths.isNotEmpty) {
      widget.onPasteLocalFiles(paths);
    }
  }

  bool get _acceptsLocalFiles => widget.enabled && widget.acceptsLocalFiles;
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: theme.colorScheme.background.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.colorScheme.border),
            ),
            child: Text(
              '松开以上传',
              style: TextStyle(
                color: theme.colorScheme.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasteFilesIntent extends Intent {
  const _PasteFilesIntent();
}

class _CopyFilesIntent extends Intent {
  const _CopyFilesIntent();
}
