// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页选区动作：集中处理右键批量菜单触发的上传、新建与多对象操作。

extension _FileManagerPageSelectedActions on _FileManagerPageState {
  Future<void> _handleSelectedObjectsAction(FileSelectionAction action) async {
    if (!mounted || _activeBucket == null) {
      return;
    }
    if (action == FileSelectionAction.refresh) {
      await _loadObjects(_activeBucketEntry!, _prefix, forceRefresh: true);
      return;
    }
    if (action == FileSelectionAction.upload) {
      await _upload();
      return;
    }
    if (action == FileSelectionAction.createDirectory) {
      await _createDirectory();
      return;
    }

    final selected = _selectedObjects;
    if (selected.isEmpty) {
      return;
    }

    if (action == FileSelectionAction.download) {
      await _downloadSelectedObjects();
      return;
    }

    final isWriteAction =
        action == FileSelectionAction.copy ||
        action == FileSelectionAction.move ||
        action == FileSelectionAction.delete;
    if (isWriteAction && !_currentBucketWritable) {
      _ensureCurrentDirectoryWritable();
      return;
    }

    if (action == FileSelectionAction.copy ||
        action == FileSelectionAction.move) {
      await _copyOrMoveSelectedObjects(action, selected);
      return;
    }

    if (action == FileSelectionAction.delete) {
      await _deleteSelectedObjects();
    }
  }

  Future<void> _copyOrMoveSelectedObjects(
    FileSelectionAction action,
    List<ObjectInfo> selected,
  ) async {
    final primary = selected.first;
    final targetPath = await showObjectTargetPathDialog(
      context,
      primary,
      move: action == FileSelectionAction.move,
    );
    if (targetPath == null || targetPath.isEmpty) {
      return;
    }
    for (final object in selected) {
      final targetKey = _resolvedBatchTargetPath(
        targetPath: targetPath,
        object: object,
        selectedCount: selected.length,
      );
      await _handleObjectAction(
        object,
        action == FileSelectionAction.move
            ? FileObjectAction.move
            : FileObjectAction.copy,
        overrideTargetPath: targetKey,
        reloadAfterAction: false,
      );
    }
    if (!mounted) return;
    await _reloadObjectsAfterBucketMutation(_activeBucketEntry!, _prefix);
  }

  String _resolvedBatchTargetPath({
    required String targetPath,
    required ObjectInfo object,
    required int selectedCount,
  }) {
    final trimmed = targetPath.trim();
    if (selectedCount <= 1) {
      return trimmed;
    }
    final normalized = trimmed.replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      return object.key;
    }
    return path.join(normalized, object.displayName);
  }
}
