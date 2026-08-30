// Object action dialogs keep rename/delete prompts out of the main page file.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';

Widget _dialogActionWrap(List<Widget> actions) => SizedBox(
  width: double.infinity,
  child: Wrap(
    alignment: WrapAlignment.end,
    spacing: 10,
    runSpacing: 10,
    children: actions,
  ),
);

// DeleteDialogChoice carries the user's delete confirmation plus whether the
// objects should bypass the trash and be removed permanently.
class DeleteDialogChoice {
  const DeleteDialogChoice({required this.confirmed, required this.permanent});

  final bool confirmed;
  final bool permanent;
}

// DeleteDialogBody renders the shared confirm body: target label, an optional
// permanent-delete switch (only when the bucket soft-deletes to trash), and
// the cancel/delete actions.
class DeleteDialogBody extends StatefulWidget {
  const DeleteDialogBody({
    super.key,
    required this.targetLabel,
    required this.trashEnabled,
    required this.actionLabel,
  });

  final String targetLabel;
  final bool trashEnabled;
  final String actionLabel;

  @override
  State<DeleteDialogBody> createState() => _DeleteDialogBodyState();
}

class _DeleteDialogBodyState extends State<DeleteDialogBody> {
  bool _permanent = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (widget.targetLabel.isNotEmpty) ...[
            Text(
              widget.targetLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.trashEnabled) ...[
            ShadSwitch(
              value: _permanent,
              onChanged: (value) => setState(() => _permanent = value),
              label: const Text('永久删除'),
              sublabel: const Text('不移入回收站，删除后无法恢复'),
            ),
            const SizedBox(height: 18),
          ] else
            const SizedBox(height: 10),
          _dialogActionWrap([
            ShadButton.outline(
              onPressed: () => Navigator.of(context).pop(
                const DeleteDialogChoice(confirmed: false, permanent: false),
              ),
              child: const Text('取消'),
            ),
            ShadButton.destructive(
              onPressed: () => Navigator.of(
                context,
              ).pop(DeleteDialogChoice(confirmed: true, permanent: _permanent)),
              child: Text(widget.actionLabel),
            ),
          ]),
        ],
      ),
    );
  }
}

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
    return await showAppModal<String?>(
      context: context,
      builder: (dialogContext) => AppShadDialog(
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
              _dialogActionWrap([
                ShadButton.outline(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                ShadButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(controller.text.trim()),
                  child: const Text('保存'),
                ),
              ]),
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
  required RemoteStorageGateway api,
  required FileManagerBucketEntry bucket,
  required String initialPrefix,
}) async {
  // Restrict the picker to the active bucket because object copy/move APIs
  // operate within one bucket. The selected folder supplies the destination;
  // the source filename is retained automatically below.
  final selected = await showRemoteDirectoryPicker(
    context: context,
    api: api,
    buckets: <FileManagerBucketEntry>[bucket],
    initial: RemoteDirectoryResult(
      bucket: bucket.bucket.name,
      prefix: initialPrefix,
      profileName: bucket.profileName,
      config: bucket.config,
    ),
  );
  return selected?.prefix;
}

// objectTargetPathInDirectory converts the selected S3 directory prefix into a
// complete destination key without asking the user to reconstruct a filename.
String objectTargetPathInDirectory(String directoryPrefix, ObjectInfo object) {
  final directory = directoryPrefix
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .join('/');
  if (directory.isEmpty) {
    return object.displayName;
  }
  return '$directory/${object.displayName}';
}

Future<DeleteDialogChoice> showDeleteObjectDialog(
  BuildContext context,
  ObjectInfo object, {
  required bool trashEnabled,
}) async {
  return await showAppModal<DeleteDialogChoice>(
        context: context,
        builder: (dialogContext) => AppShadDialog(
          title: const Text('删除'),
          description: Text(
            trashEnabled
                ? object.isDir
                      ? '将把整个目录及其内容移入回收站。'
                      : '将把这个文件移入回收站。'
                : object.isDir
                ? '将删除整个目录及其内容。此操作不可撤销。'
                : '将删除这个文件。此操作不可撤销。',
          ),
          child: DeleteDialogBody(
            targetLabel: object.displayName,
            trashEnabled: trashEnabled,
            actionLabel: '删除',
          ),
        ),
      ) ??
      const DeleteDialogChoice(confirmed: false, permanent: false);
}

Future<DeleteDialogChoice> showDeleteObjectsDialog(
  BuildContext context,
  int count, {
  required bool trashEnabled,
}) async {
  return await showAppModal<DeleteDialogChoice>(
        context: context,
        builder: (dialogContext) => AppShadDialog(
          title: const Text('批量删除'),
          description: Text(
            trashEnabled
                ? '将把选中的 $count 个项目移入回收站。'
                : '将删除选中的 $count 个项目。此操作不可撤销。',
          ),
          child: DeleteDialogBody(
            targetLabel: '',
            trashEnabled: trashEnabled,
            actionLabel: '删除',
          ),
        ),
      ) ??
      const DeleteDialogChoice(confirmed: false, permanent: false);
}

Future<bool> showDeleteTrashItemDialog(
  BuildContext context,
  TrashItem item,
) async {
  return await showAppModal<bool>(
        context: context,
        builder: (dialogContext) => AppShadDialog(
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
                _dialogActionWrap([
                  ShadButton.outline(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  ShadButton.destructive(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('彻底删除'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

Future<bool> showDeleteTrashItemsDialog(BuildContext context, int count) async {
  return await showAppModal<bool>(
        context: context,
        builder: (dialogContext) => AppShadDialog(
          title: const Text('批量彻底删除'),
          description: Text('将从回收站彻底删除选中的 $count 个项目，之后无法恢复。'),
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _dialogActionWrap([
                  ShadButton.outline(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  ShadButton.destructive(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('彻底删除'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

Future<bool> showClearTrashDialog(BuildContext context, String bucket) async {
  return await showAppModal<bool>(
        context: context,
        builder: (dialogContext) => AppShadDialog(
          title: const Text('清空回收站'),
          description: Text('将彻底删除「$bucket」回收站中的所有项目，之后无法恢复。'),
          child: SizedBox(
            width: 380,
            child: _dialogActionWrap([
              ShadButton.outline(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              ShadButton.destructive(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('清空回收站'),
              ),
            ]),
          ),
        ),
      ) ??
      false;
}
