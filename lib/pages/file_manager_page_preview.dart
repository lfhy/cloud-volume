part of 'file_manager_page.dart';

// 文件预览页逻辑：维护弹窗内预览、下载进度和外部应用打开流程。

extension _FileManagerPagePreview on _FileManagerPageState {
  Future<void> _openObject(ObjectInfo object) async {
    if (_activeBucket == null) return;
    await _showObjectPreview(object);
  }

  Future<void> _showObjectPreview(ObjectInfo object) async {
    final bucket = _activeBucket;
    if (bucket == null) return;
    final kind = previewKindForName(object.displayName);
    final openWatch = Stopwatch()..start();
    unawaited(
      AppLog.debug(
        'open start bucket=$bucket key=${object.key} kind=${kind.name} size=${object.size}',
        tag: 'preview',
      ),
    );
    if (!mounted) return;
    var loading = kind == FilePreviewKind.image;
    FilePreviewTransferState? transfer;
    FilePreviewSource? source;
    String? errorText;
    // 远端对象不存在时置为 true：用于隐藏下载相关动作并在关闭弹窗后刷新目录元数据。
    var unavailable = false;

    await showAppModal(
      context: context,
      builder: (dialogContext) {
        var started = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            if (loading && !started) {
              started = true;
              final loadWatch = Stopwatch()..start();
              unawaited(
                AppLog.debug(
                  'source load start bucket=$bucket key=${object.key} sinceOpenMs=${openWatch.elapsedMilliseconds}',
                  tag: 'preview',
                ),
              );
              unawaited(
                FileAccessService.instance
                    .preparePreviewSource(
                      api: widget.api,
                      config: _activeConfig,
                      bucket: bucket,
                      object: object,
                    )
                    .then((value) {
                      unawaited(
                        AppLog.debug(
                          'source load done bucket=$bucket key=${object.key} elapsedMs=${loadWatch.elapsedMilliseconds} sinceOpenMs=${openWatch.elapsedMilliseconds}',
                          tag: 'preview',
                        ),
                      );
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        source = value;
                        loading = false;
                      });
                    })
                    .catchError((error) {
                      unawaited(
                        AppLog.error(
                          'source load failed bucket=$bucket key=${object.key} elapsedMs=${loadWatch.elapsedMilliseconds} error=$error',
                          tag: 'preview',
                        ),
                      );
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        errorText = describeBridgeError(error);
                        unavailable = isObjectMissingError(error);
                        loading = false;
                      });
                    }),
              );
            }
            return FilePreviewDialog(
              object: object,
              kind: kind,
              source: source,
              loading: loading,
              transfer: transfer,
              errorText: errorText,
              unavailable: unavailable,
              onOpenWithSystem: () {
                if (transfer != null) return;
                transfer = _runningTransferState(_PreviewTransferAction.open);
                setDialogState(() {});
                unawaited(
                  _runPreviewTransfer(
                    action: _PreviewTransferAction.open,
                    object: object,
                    dialogContext: dialogContext,
                    setDialogState: setDialogState,
                    setTransfer: (value) => transfer = value,
                    onMissingDetected: () {
                      setDialogState(() {
                        unavailable = true;
                      });
                    },
                  ),
                );
              },
              onSaveAs: () {
                if (transfer != null) return;
                unawaited(
                  _runPreviewTransfer(
                    action: _PreviewTransferAction.saveAs,
                    object: object,
                    dialogContext: dialogContext,
                    setDialogState: setDialogState,
                    setTransfer: (value) => transfer = value,
                    onMissingDetected: () {
                      setDialogState(() {
                        unavailable = true;
                      });
                    },
                  ),
                );
              },
              onDownload: () {
                if (transfer != null) return;
                transfer = _runningTransferState(
                  _PreviewTransferAction.download,
                );
                setDialogState(() {});
                unawaited(
                  _runPreviewTransfer(
                    action: _PreviewTransferAction.download,
                    object: object,
                    dialogContext: dialogContext,
                    setDialogState: setDialogState,
                    setTransfer: (value) => transfer = value,
                    onMissingDetected: () {
                      // 让 _ActionBar 立即切到 unavailable 分支，不再显示
                      // 取消下载/后台运行，并把按钮文案收敛为"关闭"。
                      setDialogState(() {
                        unavailable = true;
                      });
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
    unawaited(
      AppLog.debug(
        'dialog closed bucket=$bucket key=${object.key} sinceOpenMs=${openWatch.elapsedMilliseconds}',
        tag: 'preview',
      ),
    );
    // 弹窗关闭时无条件刷一下当前目录元数据：兼容"对象已被远端删除"
    // 的所有路径（预览加载失败、下载/另存为/外部打开返回 404，甚至用户
    // 在错误出现前就关弹窗），避免列表里继续显示已不存在的条目。
    // 刷新会带上"仍在同一 bucket/prefix"的保护，所以即使对象没被删，
    // 最多也只是多拉一次列表，不会有副作用。
    if (_activeBucketEntry != null && mounted) {
      await _refreshActiveListingIfStillCurrent();
    }
  }

  Future<void> _runPreviewTransfer({
    required _PreviewTransferAction action,
    required ObjectInfo object,
    required BuildContext dialogContext,
    required StateSetter setDialogState,
    required ValueChanged<FilePreviewTransferState?> setTransfer,
    VoidCallback? onMissingDetected,
  }) async {
    final bucket = _activeBucket;
    if (bucket == null) return;
    try {
      final request = switch (action) {
        _PreviewTransferAction.open =>
          await FileAccessService.instance.prepareObjectForExternalOpen(
            api: widget.api,
            config: _activeConfig,
            bucket: bucket,
            object: object,
          ),
        _PreviewTransferAction.saveAs =>
          await FileAccessService.instance.prepareDownloadObjectWithPicker(
            api: widget.api,
            config: _activeConfig,
            bucket: bucket,
            object: object,
          ),
        _PreviewTransferAction.download =>
          await FileAccessService.instance
              .prepareDownloadObjectToDefaultDirectory(
                api: widget.api,
                config: _activeConfig,
                bucket: bucket,
                object: object,
              ),
      };
      if (request == null) {
        if (!dialogContext.mounted) return;
        setDialogState(() => setTransfer(null));
        return;
      }
      if (!dialogContext.mounted) return;
      setDialogState(() {
        setTransfer(_runningTransferState(action, task: request.task));
      });
      final localPath = await request.completion;
      if (action == _PreviewTransferAction.open) {
        await FileAccessService.instance.openLocalPath(localPath);
        if (!dialogContext.mounted) return;
        Navigator.of(dialogContext).pop();
        return;
      }
      if (!dialogContext.mounted) return;
      setDialogState(() {
        setTransfer(_doneTransferState(action, task: request.task));
      });
    } catch (error) {
      if (!dialogContext.mounted) {
        _showPageError(error);
        return;
      }
      final missing = isObjectMissingError(error);
      if (missing) {
        // 远端对象已不存在：立即触发一次目录元数据刷新，让已删除的条目
        // 从列表中消失，不依赖弹窗被关闭的时机（用户可能直接关弹窗而
        // 非"取消"，原来的关闭后判定会漏掉）。
        unawaited(_refreshActiveListingIfStillCurrent());
        onMissingDetected?.call();
      }
      setDialogState(() {
        setTransfer(
          _runningTransferState(action, errorText: describeBridgeError(error)),
        );
      });
    }
  }

  // 仅当用户仍在同一个 bucket/prefix 时才刷新，避免页面已切走的误刷新。
  Future<void> _refreshActiveListingIfStillCurrent() async {
    final entry = _activeBucketEntry;
    final prefix = _prefix;
    if (entry == null || !mounted) return;
    if (_activeBucketId != entry.id || _prefix != prefix) return;
    await _reloadObjectsAfterBucketMutation(entry, prefix);
  }

  FilePreviewTransferState _runningTransferState(
    _PreviewTransferAction action, {
    TransferTask? task,
    String? errorText,
  }) {
    return FilePreviewTransferState(
      runningTitle: action.runningTitle,
      waitingText: action.waitingText,
      doneTitle: action.doneTitle,
      doneText: action.doneText,
      taskId: task == null ? null : 'transfer:${task.id}',
      errorText: errorText,
    );
  }

  FilePreviewTransferState _doneTransferState(
    _PreviewTransferAction action, {
    TransferTask? task,
  }) {
    return FilePreviewTransferState(
      runningTitle: action.runningTitle,
      waitingText: action.waitingText,
      doneTitle: action.doneTitle,
      doneText: action.doneText,
      taskId: task == null ? null : 'transfer:${task.id}',
      done: true,
    );
  }
}

enum _PreviewTransferAction {
  open(
    runningTitle: '正在下载并准备打开',
    waitingText: '下载完成后会自动使用外部应用打开。',
    doneTitle: '已打开',
    doneText: '文件已交给系统应用打开。',
  ),
  saveAs(
    runningTitle: '正在另存为',
    waitingText: '文件正在保存到你选择的位置。',
    doneTitle: '另存为完成',
    doneText: '文件已保存到本地。',
  ),
  download(
    runningTitle: '正在下载',
    waitingText: '文件正在保存到默认下载目录。',
    doneTitle: '下载完成',
    doneText: '文件已保存到默认下载目录。',
  );

  const _PreviewTransferAction({
    required this.runningTitle,
    required this.waitingText,
    required this.doneTitle,
    required this.doneText,
  });

  final String runningTitle;
  final String waitingText;
  final String doneTitle;
  final String doneText;
}
