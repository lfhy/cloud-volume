// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页操作逻辑：上传、目录创建、对象打开/下载以及右键动作。

extension _FileManagerPageActions on _FileManagerPageState {
  Future<void> _upload() async {
    if (_activeBucket == null) return;
    if (!_ensureCurrentDirectoryWritable()) return;
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: widget.api.capabilities.supportsBrowserTransfers,
    );
    if (result == null || result.files.isEmpty) return;
    final tasks = <TransferTask>[];
    for (final file in result.files) {
      final path = file.path;
      final bytes = file.bytes;
      if (path == null && bytes == null) {
        continue;
      }
      if (bytes != null) {
        final task = _queueBrowserUpload(file.name, bytes);
        if (task != null) {
          tasks.add(task);
        }
      } else if (path != null) {
        final task = _queueLocalUpload(path);
        if (task != null) {
          tasks.add(task);
        }
      }
    }
    await _showUploadProgressDialogForTasks(tasks);
  }

  TransferTask? _queueLocalUpload(String localPath, {String? relativeKey}) {
    if (_activeBucket == null ||
        _activeBucketEntry == null ||
        localPath.trim().isEmpty) {
      return null;
    }
    if (!_ensureCurrentDirectoryWritable()) return null;
    final bucket = _activeBucket!;
    final uploadKey = relativeKey == null || relativeKey.trim().isEmpty
        ? path.basename(localPath)
        : relativeKey;
    final key = _prefix + uploadKey;
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.upload,
      bucket: bucket,
      key: key,
      localPath: localPath,
    );
    unawaited(_runUploadTask(task, _activeBucketEntry!));
    return task;
  }

  TransferTask? _queueBrowserUpload(String fileName, Uint8List bytes) {
    if (_activeBucket == null || _activeBucketEntry == null) return null;
    if (!_ensureCurrentDirectoryWritable()) return null;
    final bucket = _activeBucket!;
    final key = _prefix + fileName;
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.upload,
      bucket: bucket,
      key: key,
      localPath: fileName,
    );
    unawaited(
      _runBrowserUploadTask(task, _activeBucketEntry!, bytes, fileName),
    );
    return task;
  }

  Future<void> _createDirectory() async {
    if (_activeBucket == null) return;
    if (!_ensureCurrentDirectoryWritable()) return;
    final controller = TextEditingController();
    String? errorText;
    bool creating = false;

    await showAppModal(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return CreateDirectoryDialog(
              controller: controller,
              errorText: errorText,
              creating: creating,
              onCancel: () => Navigator.of(dialogContext).pop(),
              onCreate: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => errorText = '目录名称不能为空');
                  return;
                }
                setDialogState(() {
                  creating = true;
                  errorText = null;
                });
                try {
                  await widget.api.createDirectory(
                    _activeConfig,
                    _activeBucket!,
                    _prefix,
                    name,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  await _reloadObjectsAfterBucketMutation(
                    _activeBucketEntry!,
                    _prefix,
                  );
                } catch (error) {
                  setDialogState(() {
                    creating = false;
                    errorText = error.toString();
                  });
                }
              },
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _runUploadTask(
    TransferTask task,
    FileManagerBucketEntry bucket,
  ) async {
    try {
      await widget.api.uploadFile(
        bucket.config,
        task.bucket,
        task.key,
        task.localPath,
        task.id,
      );
      TransferQueue.instance.markTaskDone(task.id);
      // 上传成功后把本地副本 seed 进预览缓存，避免"刚传完就双击还要重下"。
      // 用原始本地路径作为源；seed 内部异常被吞掉，不影响上传成功语义。
      unawaited(
        FileAccessService.instance.seedCacheFromUpload(
          api: widget.api,
          config: bucket.config,
          bucket: task.bucket,
          key: task.key,
          localSourcePath: task.localPath,
        ),
      );
      if (!mounted || _activeBucketId != bucket.id) return;
      await _reloadObjectsAfterBucketMutation(bucket, _prefix);
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      // 即使上传失败，也刷新当前目录让部分上传的对象（或回收站里的临时分片）立即可见。
      if (mounted && _activeBucketId == bucket.id) {
        await _reloadObjectsAfterBucketMutation(bucket, _prefix);
      }
    }
  }

  Future<void> _runBrowserUploadTask(
    TransferTask task,
    FileManagerBucketEntry bucket,
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      await widget.api.uploadBytes(
        bucket.config,
        task.bucket,
        task.key,
        bytes,
        task.id,
        fileName: fileName,
      );
      TransferQueue.instance.markTaskDone(task.id);
      // 浏览器上传同样 seed 缓存（web 端实现为空操作，桌面端用上传时的 bytes）。
      unawaited(
        FileAccessService.instance.seedCacheFromUpload(
          api: widget.api,
          config: bucket.config,
          bucket: task.bucket,
          key: task.key,
          bytes: bytes,
        ),
      );
      if (!mounted || _activeBucketId != bucket.id) return;
      await _reloadObjectsAfterBucketMutation(bucket, _prefix);
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
    }
  }

  Future<void> _downloadObject(ObjectInfo object) async {
    if (_activeBucket == null) return;
    try {
      final request = FileAccessService.instance.startDownloadObjectWithPicker(
        api: widget.api,
        config: _activeConfig,
        bucket: _activeBucket!,
        object: object,
        directoryLister: _downloadDirectoryLister(),
      );
      _watchDownloadRequest(request);
      await _showDownloadProgressDialogForTasks(_tasksForRequests([request]));
    } catch (error) {
      _showPageError(error);
    }
  }

  void _watchDownloadRequest(FileAccessTransferRequest request) {
    unawaited(request.completion.then<void>((_) {}).catchError((_) {}));
  }

  List<TransferTask> _tasksForRequests(
    Iterable<FileAccessTransferRequest> requests,
  ) {
    return requests
        .map((request) => request.task)
        .whereType<TransferTask>()
        .toList(growable: false);
  }

  Future<void> _handleObjectAction(
    ObjectInfo object,
    FileObjectAction action, {
    String? overrideTargetPath,
    bool reloadAfterAction = true,
  }) async {
    if (!mounted || _activeBucket == null) return;
    try {
      if (action == FileObjectAction.open) {
        await _openObject(object);
        return;
      }
      if (action == FileObjectAction.download) {
        await _downloadObject(object);
        return;
      }
      if (action == FileObjectAction.share) {
        if (!_activeConfig.supportsShareLinks) {
          _showPageMessage(title: '暂不支持', message: '当前账号类型暂不支持创建分享链接。');
          return;
        }
        final durationSec = await showShareDurationDialog(
          context,
          title: '创建分享',
          description: '为当前文件生成一个可复制的分享链接。',
          confirmLabel: '创建分享',
        );
        if (durationSec == null) {
          return;
        }
        final shareRecord = await widget.api.createShare(
          _activeConfig,
          _activeBucket!,
          object.key,
          object.displayName,
          durationSec,
        );
        ShareRecordsNotifier.instance.markChanged();
        if (!mounted) {
          return;
        }
        await showShareLinkDialog(context, record: shareRecord);
        return;
      }
      final isWriteAction =
          action == FileObjectAction.copy ||
          action == FileObjectAction.move ||
          action == FileObjectAction.rename ||
          action == FileObjectAction.delete;
      if (isWriteAction && !_currentBucketWritable) {
        _ensureCurrentDirectoryWritable();
        return;
      }
      if (action == FileObjectAction.copy || action == FileObjectAction.move) {
        final targetDirectory =
            overrideTargetPath ??
            await showObjectTargetPathDialog(
              context,
              object,
              api: widget.api,
              bucket: _activeBucketEntry!,
              initialPrefix: _prefix,
            );
        final targetPath =
            overrideTargetPath ??
            (targetDirectory == null
                ? null
                : objectTargetPathInDirectory(targetDirectory, object));
        if (targetPath == null ||
            targetPath.isEmpty ||
            targetPath == object.key) {
          return;
        }
        final task = TransferQueue.instance.startTask(
          kind: action == FileObjectAction.move
              ? TransferKind.move
              : TransferKind.copy,
          bucket: _activeBucket!,
          key: object.key,
          localPath: '',
          targetPath: targetPath,
        );
        try {
          if (action == FileObjectAction.move) {
            await widget.api.moveObject(
              _activeConfig,
              _activeBucket!,
              object.key,
              targetPath,
              object.isDir,
              task.id,
            );
            await FileAccessService.instance.evictCacheForObject(
              api: widget.api,
              config: _activeConfig,
              bucket: _activeBucket!,
              object: object,
            );
          } else {
            await widget.api.copyObject(
              _activeConfig,
              _activeBucket!,
              object.key,
              targetPath,
              object.isDir,
              task.id,
            );
          }
          TransferQueue.instance.markTaskDone(task.id);
        } catch (error) {
          TransferQueue.instance.markTaskFailed(task.id, error);
          rethrow;
        }
      }
      if (!mounted) return;
      if (action == FileObjectAction.rename) {
        final newName = await showRenameObjectDialog(context, object);
        if (newName == null ||
            newName.isEmpty ||
            newName == object.displayName) {
          return;
        }
        final trimmedKey = object.key.replaceFirst(RegExp(r'/+$'), '');
        final slash = trimmedKey.lastIndexOf('/');
        final targetPath = slash < 0
            ? newName
            : '${trimmedKey.substring(0, slash + 1)}$newName';
        final task = TransferQueue.instance.startTask(
          kind: TransferKind.move,
          bucket: _activeBucket!,
          key: object.key,
          localPath: '',
          targetPath: targetPath,
        );
        try {
          await widget.api.renameObject(
            _activeConfig,
            _activeBucket!,
            object.key,
            object.isDir,
            newName,
            taskId: task.id,
          );
          TransferQueue.instance.markTaskDone(task.id);
        } catch (error) {
          TransferQueue.instance.markTaskFailed(task.id, error);
          rethrow;
        }
        await FileAccessService.instance.evictCacheForObject(
          api: widget.api,
          config: _activeConfig,
          bucket: _activeBucket!,
          object: object,
        );
      } else if (action == FileObjectAction.delete) {
        if (!mounted) return;
        final choice = await showDeleteObjectDialog(
          context,
          object,
          trashEnabled: _activeBucketTrashEnabled,
        );
        if (!choice.confirmed) return;
        final tasks = _queueObjectDeletes(<ObjectInfo>[
          object,
        ], permanent: choice.permanent);
        await _showDeleteProgressDialogForTasks(tasks);
        return;
      }
      if (!mounted || !reloadAfterAction) return;
      await _reloadObjectsAfterBucketMutation(_activeBucketEntry!, _prefix);
    } catch (error) {
      _showPageError(error);
    }
  }

  void _showPageSnack(String message) {
    if (!mounted) {
      return;
    }
    showAppToast(context, message: message);
  }

  void _showPageError(Object error) {
    if (!mounted) {
      return;
    }
    _showPageMessage(title: '操作失败', message: describeBridgeError(error));
  }

  void _showPageMessage({required String title, required String message}) {
    if (!mounted) {
      return;
    }
    unawaited(
      showAppModal<void>(
        context: context,
        builder: (dialogContext) => ShadDialog(
          title: Text(title),
          description: Text(message),
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: 12),
                ShadButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
