// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页操作逻辑：上传、目录创建、对象打开/下载以及右键动作。

extension _FileManagerPageActions on _FileManagerPageState {
  Future<void> _upload() async {
    if (_activeBucket == null) return;
    if (!_ensureCurrentDirectoryWritable()) return;
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) return;
    final prefix = _prefix;
    final sourceListingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
    );
    if (!_isCurrentObjectMutationCommand(
      bucketEntry,
      prefix,
      sourceListingViewGeneration,
      request,
    )) {
      return;
    }
    final result = await FilePicker.pickFiles();
    // Native file selection can remain open while a profile refresh rebinds
    // the current bucket. Do not turn that late picker result into an upload
    // through a different endpoint/root prefix.
    if (result.isEmpty ||
        !_isCurrentObjectMutationCommand(
          bucketEntry,
          prefix,
          sourceListingViewGeneration,
          request,
        )) {
      return;
    }
    final tasks = <TransferTask>[];
    for (final file in result) {
      final path = file.path;
      if (isWebPlatform) {
        final bytes = await file.readAsBytes();
        if (!_isCurrentObjectMutationCommand(
          bucketEntry,
          prefix,
          sourceListingViewGeneration,
          request,
        )) {
          return;
        }
        final task = _queueBrowserUpload(file.name, bytes);
        if (task != null) {
          tasks.add(task);
        }
      } else if (path != null) {
        if (!_isCurrentObjectMutationCommand(
          bucketEntry,
          prefix,
          sourceListingViewGeneration,
          request,
        )) {
          return;
        }
        final task = _queueLocalUpload(path);
        if (task != null) {
          tasks.add(task);
        }
      }
    }
    await _showUploadProgressDialogForTasks(tasks);
  }

  Future<void> _createDirectory() async {
    if (_activeBucket == null) return;
    if (!_ensureCurrentDirectoryWritable()) return;
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) return;
    final config = bucketEntry.config;
    final bucket = bucketEntry.bucket.name;
    final prefix = _prefix;
    final sourceListingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
    );
    if (!_isCurrentMobileFileManagerRequest(request)) return;
    final usesMetadataRemoteTasks =
        widget.api.capabilities.supportsMounts &&
        config.profileId.trim().isNotEmpty;
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
                // The confirmation sheet may have remained open while an
                // Android bootstrap refresh rebound this bucket ID. Never
                // write through the dialog's captured endpoint/root prefix.
                if (!_isCurrentObjectMutationCommand(
                  bucketEntry,
                  prefix,
                  sourceListingViewGeneration,
                  request,
                )) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  return;
                }
                setDialogState(() {
                  creating = true;
                  errorText = null;
                });
                try {
                  final taskStartedAt = DateTime.now().toUtc();
                  await widget.api.createDirectory(
                    config,
                    bucket,
                    prefix,
                    name,
                  );
                  _invalidateObjectListingCache(bucketId: bucketEntry.id);
                  if (usesMetadataRemoteTasks) {
                    _trackMetadataTaskForRefresh(
                      bucketId: bucketEntry.id,
                      bucket: bucket,
                      profileId: config.profileId,
                      prefix: prefix,
                      path: prefix + name,
                      startedAt: taskStartedAt,
                      sourceListingViewGeneration: sourceListingViewGeneration,
                    );
                  }
                  if (!mounted || !dialogContext.mounted) {
                    return;
                  }
                  Navigator.of(dialogContext).pop();
                  if (!_isCurrentObjectMutationCommand(
                    bucketEntry,
                    prefix,
                    sourceListingViewGeneration,
                    request,
                  )) {
                    return;
                  }
                  await _reloadObjectsAfterBucketMutation(bucketEntry, prefix);
                } catch (error) {
                  final requestWasCurrent = _isCurrentObjectMutationCommand(
                    bucketEntry,
                    prefix,
                    sourceListingViewGeneration,
                    request,
                  );
                  unawaited(
                    _recoverObjectsAfterUncertainMutation(
                      bucketEntry,
                      prefix,
                      sourceListingViewGeneration,
                    ),
                  );
                  if (!dialogContext.mounted || !requestWasCurrent) {
                    return;
                  }
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
    if (!mounted) return;
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) return;
    final bucket = bucketEntry.bucket.name;
    final config = bucketEntry.config;
    final prefix = _prefix;
    final sourceListingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
    );
    if (!_isCurrentMobileFileManagerRequest(request)) return;
    var writeMayHaveMutated = false;
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
        if (!config.supportsShareLinks) {
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
        if (!_isCurrentObjectMutationCommand(
          bucketEntry,
          prefix,
          sourceListingViewGeneration,
          request,
        )) {
          return;
        }
        final shareRecord = await widget.api.createShare(
          config,
          bucket,
          object.key,
          object.displayName,
          durationSec,
        );
        ShareRecordsNotifier.instance.markChanged();
        if (!mounted || !_isCurrentMobileFileManagerRequest(request)) {
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
              bucket: bucketEntry,
              initialPrefix: prefix,
            );
        final targetPath =
            overrideTargetPath ??
            (targetDirectory == null
                ? null
                : objectTargetPathInDirectory(targetDirectory, object));
        if (targetPath == null ||
            targetPath.isEmpty ||
            targetPath == object.key ||
            !_isCurrentObjectMutationCommand(
              bucketEntry,
              prefix,
              sourceListingViewGeneration,
              request,
            )) {
          return;
        }
        final task = TransferQueue.instance.startTask(
          kind: action == FileObjectAction.move
              ? TransferKind.move
              : TransferKind.copy,
          bucket: bucket,
          key: object.key,
          localPath: '',
          targetPath: targetPath,
          publishRemoteTask:
              action != FileObjectAction.move || !_usesMetadataRemoteTasks,
        );
        try {
          if (action == FileObjectAction.move) {
            writeMayHaveMutated = true;
            await widget.api.moveObject(
              config,
              bucket,
              object.key,
              targetPath,
              object.isDir,
              task.id,
            );
            _invalidateObjectListingCache(bucketId: bucketEntry.id);
            await FileAccessService.instance.evictCacheForObject(
              api: widget.api,
              config: config,
              bucket: bucket,
              object: object,
            );
          } else {
            writeMayHaveMutated = true;
            await widget.api.copyObject(
              config,
              bucket,
              object.key,
              targetPath,
              object.isDir,
              task.id,
            );
            _invalidateObjectListingCache(bucketId: bucketEntry.id);
          }
          TransferQueue.instance.markTaskDone(task.id);
        } catch (error) {
          TransferQueue.instance.markTaskFailed(task.id, error);
          rethrow;
        }
      }
      if (!mounted) return;
      if (action == FileObjectAction.rename) {
        if (!_isCurrentObjectMutationCommand(
          bucketEntry,
          prefix,
          sourceListingViewGeneration,
          request,
        )) {
          return;
        }
        final newName = await showRenameObjectDialog(context, object);
        if (newName == null ||
            newName.isEmpty ||
            newName == object.displayName ||
            !_isCurrentObjectMutationCommand(
              bucketEntry,
              prefix,
              sourceListingViewGeneration,
              request,
            )) {
          return;
        }
        final trimmedKey = object.key.replaceFirst(RegExp(r'/+$'), '');
        final slash = trimmedKey.lastIndexOf('/');
        final targetPath = slash < 0
            ? newName
            : '${trimmedKey.substring(0, slash + 1)}$newName';
        final task = TransferQueue.instance.startTask(
          kind: TransferKind.move,
          bucket: bucket,
          key: object.key,
          localPath: '',
          targetPath: targetPath,
          publishRemoteTask: !_usesMetadataRemoteTasks,
        );
        try {
          writeMayHaveMutated = true;
          await widget.api.renameObject(
            config,
            bucket,
            object.key,
            object.isDir,
            newName,
            taskId: task.id,
          );
          _invalidateObjectListingCache(bucketId: bucketEntry.id);
          TransferQueue.instance.markTaskDone(task.id);
        } catch (error) {
          TransferQueue.instance.markTaskFailed(task.id, error);
          rethrow;
        }
        await FileAccessService.instance.evictCacheForObject(
          api: widget.api,
          config: config,
          bucket: bucket,
          object: object,
        );
      } else if (action == FileObjectAction.delete) {
        if (!mounted ||
            !_isCurrentObjectMutationCommand(
              bucketEntry,
              prefix,
              sourceListingViewGeneration,
              request,
            )) {
          return;
        }
        final choice = await showDeleteObjectDialog(
          context,
          object,
          trashEnabled: _activeBucketTrashEnabled,
        );
        if (!choice.confirmed ||
            !_isCurrentObjectMutationCommand(
              bucketEntry,
              prefix,
              sourceListingViewGeneration,
              request,
            )) {
          return;
        }
        final tasks = _queueObjectDeletes(<ObjectInfo>[
          object,
        ], permanent: choice.permanent);
        await _showDeleteProgressDialogForTasks(tasks);
        return;
      }
      if (!reloadAfterAction ||
          !_isCurrentObjectMutationCommand(
            bucketEntry,
            prefix,
            sourceListingViewGeneration,
            request,
          )) {
        return;
      }
      await _reloadObjectsAfterBucketMutation(bucketEntry, prefix);
    } catch (error) {
      final requestWasCurrent = _isCurrentObjectMutationCommand(
        bucketEntry,
        prefix,
        sourceListingViewGeneration,
        request,
      );
      if (requestWasCurrent) {
        _showPageError(error);
      }
      if (writeMayHaveMutated) {
        if (reloadAfterAction) {
          unawaited(
            _recoverObjectsAfterUncertainMutation(
              bucketEntry,
              prefix,
              sourceListingViewGeneration,
            ),
          );
        } else {
          // A batch retains its captured request until its single final
          // refresh. Advancing the mobile epoch here would skip later rows.
          _invalidateObjectListingCache(bucketId: bucketEntry.id);
        }
      }
    }
  }
}
