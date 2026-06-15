part of 'file_manager_page.dart';

// 文件管理页批量任务反馈：统一弹出进度拟态框，允许关闭后继续后台运行。

extension _FileManagerPageUploadFeedback on _FileManagerPageState {
  Future<void> _showUploadProgressDialogForTasks(
    List<TransferTask> tasks,
  ) async {
    await _showBatchTaskProgressDialogForTasks(
      tasks,
      mode: BatchTaskProgressMode.upload,
      backgroundMessage: '上传已转为后台进行',
    );
  }

  Future<void> _showDeleteProgressDialogForTasks(
    List<TransferTask> tasks,
  ) async {
    await _showBatchTaskProgressDialogForTasks(
      tasks,
      mode: BatchTaskProgressMode.delete,
      backgroundMessage: '删除已转为后台进行',
    );
  }

  Future<void> _showDownloadProgressDialogForTasks(
    List<TransferTask> tasks,
  ) async {
    await _showBatchTaskProgressDialogForTasks(
      tasks,
      mode: BatchTaskProgressMode.download,
      backgroundMessage: '下载已转为后台进行',
    );
  }

  Future<void> _showBatchTaskProgressDialogForTasks(
    List<TransferTask> tasks, {
    required BatchTaskProgressMode mode,
    required String backgroundMessage,
  }) async {
    if (!mounted || tasks.isEmpty) {
      return;
    }
    final taskIds = tasks.map((task) => task.id).toList(growable: false);
    TransferQueue.instance.markTasksForeground(taskIds);
    try {
      await showShadDialog<void>(
        context: context,
        builder: (dialogContext) => BatchTaskProgressDialog(
          taskIds: taskIds,
          currentPathLabel: _uploadTargetLabel,
          mode: mode,
          onRunInBackground: () {
            Navigator.of(dialogContext).pop();
            _showPageSnack(backgroundMessage);
          },
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      );
    } finally {
      TransferQueue.instance.clearTasksForeground(taskIds);
    }
  }

  String get _uploadTargetLabel {
    final bucket = _activeBucket;
    if (bucket == null) {
      return '';
    }
    if (_prefix.isEmpty) {
      return bucket;
    }
    return '$bucket / $_prefix';
  }
}
