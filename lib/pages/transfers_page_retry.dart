part of 'transfers_page.dart';

// 任务队列重试逻辑：只重跑有明确本地路径的单文件上传/下载。
extension _TransfersPageRetry on _TransfersPageState {
  Future<void> _retryFileTransfer(TransferTask task) async {
    if (!task.isRetryableFileTransfer) {
      return;
    }
    TransferQueue.instance.markTaskRunning(
      task.id,
      statusDetail: task.isDirectoryChild ? 'directory_child' : '',
      totalBytes: task.totalBytes,
      resetProgress: true,
    );
    try {
      if (task.isUpload) {
        await widget.api.uploadFile(
          widget.config,
          task.bucket,
          task.key,
          task.localPath,
          task.id,
        );
      } else {
        await widget.api.downloadFile(
          widget.config,
          task.bucket,
          task.key,
          task.localPath,
          task.id,
        );
      }
      TransferQueue.instance.markTaskDone(task.id);
      if (mounted) {
        showAppToast(context, title: '重试完成', message: task.displayName);
      }
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      if (mounted) {
        showAppErrorToast(context, title: '重试失败', message: error.toString());
      }
    }
  }
}
