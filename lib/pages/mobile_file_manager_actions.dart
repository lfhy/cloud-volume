// Android file-page action sheets: keep dense file commands out of the
// touch-first page layout while reusing the shared workspace mutations.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _MobileFileManagerAction {
  const _MobileFileManagerAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool destructive;
}

/// Opens the context-aware action sheet from the Android top bar or FAB.
Future<void> showMobileFileManagerActions(
  BuildContext context,
  FileManagerWorkspaceController workspace, {
  bool fromFab = false,
}) async {
  final actions = <_MobileFileManagerAction>[];
  if (workspace.hasSelectedObjects) {
    if (workspace.selectedObjects.any((object) => !object.isDir)) {
      actions.add(
        _MobileFileManagerAction(
          label: '批量下载',
          icon: LucideIcons.download,
          onPressed: () => unawaited(workspace.downloadSelected()),
        ),
      );
    }
    if (workspace.currentBucketWritable) {
      actions.add(
        _MobileFileManagerAction(
          label: '批量删除',
          icon: LucideIcons.trash2,
          onPressed: () => unawaited(workspace.deleteSelected()),
          destructive: true,
        ),
      );
    }
    actions.add(
      _MobileFileManagerAction(
        label: '取消选择',
        icon: LucideIcons.x,
        onPressed: workspace.clearSelection,
      ),
    );
  } else if (workspace.hasActiveBucket && !workspace.isShowingTrash) {
    if (workspace.currentDirectoryWritable) {
      actions.addAll([
        _MobileFileManagerAction(
          label: '上传文件',
          icon: LucideIcons.upload,
          onPressed: () => unawaited(workspace.upload()),
        ),
        _MobileFileManagerAction(
          label: '新建文件夹',
          icon: LucideIcons.folderPlus,
          onPressed: () => unawaited(workspace.createDirectory()),
        ),
      ]);
    }
    if (workspace.activeBucketTrashEnabled) {
      actions.add(
        _MobileFileManagerAction(
          label: '打开回收站',
          icon: LucideIcons.trash2,
          onPressed: () => unawaited(workspace.openTrash()),
        ),
      );
    }
    actions.add(
      _MobileFileManagerAction(
        label: '刷新',
        icon: LucideIcons.refreshCw,
        onPressed: () => unawaited(workspace.refresh()),
      ),
    );
  } else if (workspace.isShowingTrash) {
    actions.add(
      _MobileFileManagerAction(
        label: '返回文件',
        icon: LucideIcons.folderOpen,
        onPressed: () => unawaited(workspace.closeTrash()),
      ),
    );
    if (workspace.hasTrashItems) {
      actions.add(
        _MobileFileManagerAction(
          label: '清空回收站',
          icon: LucideIcons.trash,
          onPressed: () => unawaited(workspace.clearTrash()),
          destructive: true,
        ),
      );
    }
    actions.add(
      _MobileFileManagerAction(
        label: '刷新',
        icon: LucideIcons.refreshCw,
        onPressed: () => unawaited(workspace.refresh()),
      ),
    );
  } else {
    actions.add(
      _MobileFileManagerAction(
        label: '刷新存储桶',
        icon: LucideIcons.refreshCw,
        onPressed: () => unawaited(workspace.refresh()),
      ),
    );
    if (workspace.canOpenAccountManagement) {
      actions.add(
        _MobileFileManagerAction(
          label: '账号管理',
          icon: LucideIcons.cloudCog,
          onPressed: workspace.openAccountManagement,
        ),
      );
    }
  }
  if (actions.isEmpty) return;
  await _showMobileActionSheet(context, fromFab ? '添加' : '操作', actions);
}

/// Shows bucket-specific commands for the Android row overflow button.
Future<void> showMobileBucketActions(
  BuildContext context,
  FileManagerWorkspaceController workspace,
  FileManagerBucketEntry bucket,
) async {
  final actions = <_MobileFileManagerAction>[
    _MobileFileManagerAction(
      label: '打开存储桶',
      icon: LucideIcons.folderOpen,
      onPressed: () => unawaited(workspace.openBucket(bucket)),
    ),
    _MobileFileManagerAction(
      label: '桶设置',
      icon: LucideIcons.settings2,
      onPressed: () => unawaited(workspace.configureBucket(bucket)),
    ),
  ];
  if (workspace.bucketTrashEnabled(bucket)) {
    actions.add(
      _MobileFileManagerAction(
        label: '打开回收站',
        icon: LucideIcons.trash2,
        onPressed: () => unawaited(workspace.openTrash(bucket)),
      ),
    );
  }
  await _showMobileActionSheet(context, '存储桶操作', actions);
}

/// Shows file-specific commands for the Android row overflow button.
Future<void> showMobileObjectActions(
  BuildContext context,
  FileManagerWorkspaceController workspace,
  ObjectInfo object,
) async {
  final actions = <_MobileFileManagerAction>[
    _MobileFileManagerAction(
      label: object.isDir ? '打开文件夹' : '打开',
      icon: LucideIcons.folderOpen,
      onPressed: object.isDir
          ? () => unawaited(workspace.openDirectory(object.key))
          : () => unawaited(workspace.openFile(object)),
    ),
  ];
  if (!object.isDir || workspace.supportsDirectoryDownload) {
    actions.add(
      _MobileFileManagerAction(
        label: '下载',
        icon: LucideIcons.download,
        onPressed: () => unawaited(
          workspace.performObjectAction(object, FileObjectAction.download),
        ),
      ),
    );
  }
  if (workspace.supportsShareLinks && !object.isDir) {
    actions.add(
      _MobileFileManagerAction(
        label: '分享',
        icon: LucideIcons.share2,
        onPressed: () => unawaited(
          workspace.performObjectAction(object, FileObjectAction.share),
        ),
      ),
    );
  }
  if (!workspace.activeBucketReadOnly) {
    actions.addAll([
      _MobileFileManagerAction(
        label: '复制',
        icon: LucideIcons.copy,
        onPressed: () => unawaited(
          workspace.performObjectAction(object, FileObjectAction.copy),
        ),
      ),
      _MobileFileManagerAction(
        label: '移动',
        icon: LucideIcons.move,
        onPressed: () => unawaited(
          workspace.performObjectAction(object, FileObjectAction.move),
        ),
      ),
      _MobileFileManagerAction(
        label: '重命名',
        icon: LucideIcons.pencil,
        onPressed: () => unawaited(
          workspace.performObjectAction(object, FileObjectAction.rename),
        ),
      ),
      _MobileFileManagerAction(
        label: '删除',
        icon: LucideIcons.trash2,
        onPressed: () => unawaited(
          workspace.performObjectAction(object, FileObjectAction.delete),
        ),
        destructive: true,
      ),
    ]);
  }
  await _showMobileActionSheet(context, '文件操作', actions);
}

/// Shows recycle-bin commands for a single Android row.
Future<void> showMobileTrashActions(
  BuildContext context,
  FileManagerWorkspaceController workspace,
  TrashItem item,
) {
  return _showMobileActionSheet(context, '回收站操作', [
    _MobileFileManagerAction(
      label: '恢复',
      icon: LucideIcons.rotateCcw,
      onPressed: () => unawaited(workspace.restoreTrashItem(item)),
    ),
    _MobileFileManagerAction(
      label: '彻底删除',
      icon: LucideIcons.trash2,
      onPressed: () => unawaited(workspace.deleteTrashItemPermanently(item)),
      destructive: true,
    ),
  ]);
}

Future<void> _showMobileActionSheet(
  BuildContext context,
  String title,
  List<_MobileFileManagerAction> actions,
) {
  return showAppModal<void>(
    context: context,
    builder: (dialogContext) {
      final theme = ShadTheme.of(dialogContext);
      return AppShadDialog(
        title: Text(title),
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final action in actions) ...[
                if (actions.first != action) const SizedBox(height: 6),
                ShadButton.ghost(
                  width: double.infinity,
                  height: 48,
                  leading: Icon(
                    action.icon,
                    size: 19,
                    color: action.destructive
                        ? theme.colorScheme.destructive
                        : theme.colorScheme.primary,
                  ),
                  mainAxisAlignment: MainAxisAlignment.start,
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    action.onPressed();
                  },
                  child: Text(
                    action.label,
                    style: TextStyle(
                      color: action.destructive
                          ? theme.colorScheme.destructive
                          : theme.colorScheme.foreground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
