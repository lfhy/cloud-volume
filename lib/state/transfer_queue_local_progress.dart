part of 'transfer_queue.dart';

// Local progress updates cover Dart-managed transfer work that has no Go snapshot.
extension TransferQueueLocalProgress on TransferQueue {
  void markTaskSelectingPath(String id) {
    final task = _taskById(id);
    if (task == null || task.isFinished) return;
    task.status = TransferStatus.pending;
    task.statusDetail = 'selecting_path';
    task.error = null;
    _publishRemoteTask(task);
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    _ensurePolling();
  }

  void markTaskScanning(String id) {
    final task = _taskById(id);
    if (task == null || task.isFinished) return;
    task.status = TransferStatus.running;
    task.statusDetail = 'scanning';
    task.error = null;
    _publishRemoteTask(task);
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    _ensurePolling();
  }

  void markTaskRunning(
    String id, {
    String statusDetail = '',
    int? totalBytes,
    bool resetProgress = false,
  }) {
    final task = _taskById(id);
    if (task == null || (task.isFinished && !resetProgress)) return;
    task.status = TransferStatus.running;
    task.statusDetail = statusDetail;
    task.error = null;
    if (resetProgress) {
      task.bytesCompleted = 0;
      task.itemsCompleted = 0;
      task.speedBytes = 0;
      task.currentFileKey = '';
      task.currentFileBytesCompleted = 0;
      task.currentFileTotalBytes = 0;
    }
    if (totalBytes != null) {
      task.totalBytes = totalBytes;
    }
    _publishRemoteTask(task);
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    _ensurePolling();
  }

  void updateTaskLocalPath(String id, String localPath) {
    final task = _taskById(id);
    if (task == null || task.isFinished) return;
    task.localPath = localPath;
    _publishRemoteTask(task);
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
  }

  void updateTaskDirectoryTotals(
    String id, {
    required int totalItems,
    required int totalBytes,
  }) {
    final task = _taskById(id);
    if (task == null || task.isFinished) return;
    task.status = TransferStatus.running;
    task.statusDetail = '';
    task.totalItems = totalItems;
    task.totalBytes = totalBytes;
    task.error = null;
    _publishRemoteTask(task);
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    _ensurePolling();
  }

  void updateTaskCurrentFile(
    String id, {
    required String key,
    required int totalBytes,
  }) {
    final task = _taskById(id);
    if (task == null || task.isFinished) return;
    task.currentFileKey = key;
    task.currentFileBytesCompleted = 0;
    task.currentFileTotalBytes = totalBytes;
    _publishRemoteTask(task);
    _scheduleNotifyListeners();
  }

  void advanceTaskDirectoryFile(String id, {required int bytes}) {
    final task = _taskById(id);
    if (task == null || task.isFinished) return;
    task.itemsCompleted += 1;
    task.bytesCompleted += bytes;
    task.currentFileKey = '';
    task.currentFileBytesCompleted = 0;
    task.currentFileTotalBytes = 0;
    _publishRemoteTask(task);
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
  }
}
