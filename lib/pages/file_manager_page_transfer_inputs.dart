// 文件管理页文件输入：处理拖拽上传、剪贴板上传，以及复制远端文件到系统剪贴板。

part of 'file_manager_page.dart';

extension _FileManagerPageTransferInputs on _FileManagerPageState {
  Future<void> _uploadLocalPaths(List<String> localPaths) async {
    if (!_acceptsFileTransferInput || localPaths.isEmpty) {
      return;
    }
    if (!_ensureCurrentDirectoryWritable()) return;
    final bucket = _activeBucketEntry;
    if (bucket == null) {
      return;
    }
    final entries = await DesktopFileTransferService.instance
        .localUploadEntries(localPaths);
    final tasks = <TransferTask>[];
    for (final entry in entries) {
      final task = entry.isDirectory
          ? _queueLocalDirectoryUpload(entry.localPath)
          : _queueLocalUpload(entry.localPath, relativeKey: entry.relativeKey);
      if (task != null) {
        tasks.add(task);
      }
    }
    await _showUploadProgressDialogForTasks(tasks);
  }

  TransferTask? _queueLocalDirectoryUpload(String localPath) {
    if (_activeBucket == null ||
        _activeBucketEntry == null ||
        localPath.trim().isEmpty) {
      return null;
    }
    if (!_ensureCurrentDirectoryWritable()) return null;
    final bucket = _activeBucket!;
    final targetPrefix = _prefix;
    final key = targetPrefix + path.basename(localPath);
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.upload,
      bucket: bucket,
      key: key,
      localPath: localPath,
    );
    unawaited(_runUploadDirectoryTask(task, _activeBucketEntry!, targetPrefix));
    return task;
  }

  Future<void> _runUploadDirectoryTask(
    TransferTask task,
    FileManagerBucketEntry bucket,
    String targetPrefix,
  ) async {
    try {
      await widget.api.uploadDirectory(
        bucket.config,
        task.bucket,
        targetPrefix,
        task.localPath,
        task.id,
      );
      _trackUploadTaskForRefresh(task.id, bucket.id, targetPrefix);
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
    }
  }

  Future<void> _copySelectedObjectsToClipboard() async {
    if (_activeBucket == null) {
      return;
    }
    final files = _selectedObjects.where((object) => !object.isDir).toList();
    if (files.isEmpty) {
      return;
    }
    try {
      final localPaths = <String>[];
      for (final object in files) {
        final localPath = await FileAccessService.instance.prepareLocalCopyPath(
          api: widget.api,
          config: _activeConfig,
          bucket: _activeBucket!,
          object: object,
        );
        localPaths.add(localPath);
      }
      await DesktopFileTransferService.instance.writeLocalFilesToClipboard(
        localPaths,
      );
      _showPageSnack('已复制 ${localPaths.length} 个文件，可粘贴到本地目录');
    } catch (error) {
      _showPageError(error);
    }
  }
}
