// Object action dialogs keep rename/delete prompts out of the main page file.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum FileObjectAction { open, download, share, copy, move, rename, delete }

enum FileSelectionAction {
  refresh,
  upload,
  createDirectory,
  download,
  copy,
  move,
  delete,
}

List<Widget> buildObjectActionMenuItems({
  required ObjectInfo object,
  required VoidCallback onOpen,
  required VoidCallback? onCopy,
  required VoidCallback? onMove,
  required VoidCallback? onRename,
  required VoidCallback? onDelete,
  VoidCallback? onShare,
  VoidCallback? onDownload,
}) {
  return <Widget>[
    ShadContextMenuItem(
      onPressed: onOpen,
      child: Text(object.isDir ? '打开' : '预览'),
    ),
    if (onDownload != null)
      ShadContextMenuItem(onPressed: onDownload, child: const Text('下载')),
    if (!object.isDir && onShare != null)
      ShadContextMenuItem(onPressed: onShare, child: const Text('创建分享')),
    if (onCopy != null)
      ShadContextMenuItem(onPressed: onCopy, child: const Text('复制到...')),
    if (onMove != null)
      ShadContextMenuItem(onPressed: onMove, child: const Text('移动到...')),
    if (onRename != null)
      ShadContextMenuItem(onPressed: onRename, child: const Text('重命名')),
    if (onDelete != null)
      ShadContextMenuItem(onPressed: onDelete, child: const Text('删除')),
  ];
}

List<Widget> buildSelectionActionMenuItems({
  required int selectedCount,
  VoidCallback? onRefresh,
  VoidCallback? onUpload,
  VoidCallback? onCreateDirectory,
  VoidCallback? onDownload,
  VoidCallback? onCopy,
  VoidCallback? onMove,
  VoidCallback? onDelete,
}) {
  final items = <Widget>[
    if (onCreateDirectory != null)
      ShadContextMenuItem(
        onPressed: onCreateDirectory,
        child: const Text('新建目录'),
      ),
    if (onRefresh != null)
      ShadContextMenuItem(onPressed: onRefresh, child: const Text('刷新')),
    if (onUpload != null)
      ShadContextMenuItem(onPressed: onUpload, child: const Text('上传')),
  ];
  if (selectedCount <= 0) {
    return items;
  }
  return <Widget>[
    ...items,
    if (onDownload != null)
      ShadContextMenuItem(
        onPressed: onDownload,
        child: Text(selectedCount == 1 ? '下载' : '批量下载'),
      ),
    if (onCopy != null)
      ShadContextMenuItem(
        onPressed: onCopy,
        child: Text(selectedCount == 1 ? '复制到...' : '批量复制到...'),
      ),
    if (onMove != null)
      ShadContextMenuItem(
        onPressed: onMove,
        child: Text(selectedCount == 1 ? '移动到...' : '批量移动到...'),
      ),
    if (onDelete != null)
      ShadContextMenuItem(
        onPressed: onDelete,
        child: Text(selectedCount == 1 ? '删除' : '批量删除'),
      ),
  ];
}

Future<String?> showRenameObjectDialog(
  BuildContext context,
  ObjectInfo object,
) async {
  final controller = TextEditingController(text: object.displayName);
  try {
    return await showShadDialog<String?>(
      context: context,
      builder: (dialogContext) => ShadDialog(
        title: const Text('重命名'),
        description: Text(object.isDir ? '输入新的目录名称。' : '输入新的文件名称。'),
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              ShadInput(controller: controller),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.outline(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  ShadButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(controller.text.trim()),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<String?> showObjectTargetPathDialog(
  BuildContext context,
  ObjectInfo object, {
  required bool move,
}) async {
  final controller = TextEditingController(text: object.key);
  try {
    return await showShadDialog<String?>(
      context: context,
      builder: (dialogContext) => ShadDialog(
        title: Text(move ? '移动到' : '复制到'),
        description: const Text('输入相对于当前存储桶根目录的目标路径。'),
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                object.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ShadInput(controller: controller),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.outline(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  ShadButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(controller.text.trim()),
                    child: Text(move ? '移动' : '复制'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<bool> showDeleteObjectDialog(
  BuildContext context,
  ObjectInfo object,
) async {
  return await showShadDialog<bool>(
        context: context,
        builder: (dialogContext) => ShadDialog(
          title: const Text('删除'),
          description: Text(
            object.isDir ? '将删除整个目录及其内容。此操作不可撤销。' : '将删除这个文件。此操作不可撤销。',
          ),
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  object.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShadButton.outline(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 10),
                    ShadButton.destructive(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

Future<bool> showDeleteObjectsDialog(BuildContext context, int count) async {
  return await showShadDialog<bool>(
        context: context,
        builder: (dialogContext) => ShadDialog(
          title: const Text('批量删除'),
          description: Text('将删除选中的 $count 个项目。此操作不可撤销。'),
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShadButton.outline(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 10),
                    ShadButton.destructive(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

Future<bool> showDeleteTrashItemDialog(
  BuildContext context,
  TrashItem item,
) async {
  return await showShadDialog<bool>(
        context: context,
        builder: (dialogContext) => ShadDialog(
          title: const Text('彻底删除'),
          description: const Text('将从回收站彻底删除，之后无法恢复。'),
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShadButton.outline(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 10),
                    ShadButton.destructive(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('彻底删除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

Future<bool> showDeleteTrashItemsDialog(BuildContext context, int count) async {
  return await showShadDialog<bool>(
        context: context,
        builder: (dialogContext) => ShadDialog(
          title: const Text('批量彻底删除'),
          description: Text('将从回收站彻底删除选中的 $count 个项目，之后无法恢复。'),
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShadButton.outline(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 10),
                    ShadButton.destructive(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('彻底删除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

Future<bool> showClearTrashDialog(BuildContext context, String bucket) async {
  return await showShadDialog<bool>(
        context: context,
        builder: (dialogContext) => ShadDialog(
          title: const Text('清空回收站'),
          description: Text('将彻底删除「$bucket」回收站中的所有项目，之后无法恢复。'),
          child: SizedBox(
            width: 380,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 10),
                ShadButton.destructive(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('清空回收站'),
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}
