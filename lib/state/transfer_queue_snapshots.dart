part of 'transfer_queue.dart';

// Remote snapshot updates keep the legacy queue alive as an execution facade.
extension TransferQueueSnapshots on TransferQueue {
  void refreshFromSnapshots(List<TransferSnapshot> snapshots) {
    var changed = false;
    var shouldPersist = false;
    for (final snapshot in snapshots) {
      final task =
          _taskById(snapshot.id) ??
          (() {
            changed = true;
            shouldPersist = true;
            return _addRemoteTask(snapshot);
          })();
      final nextStatus = _statusFromWire(snapshot.status);
      final canceled = _cancelRequestedIds.contains(snapshot.id);
      final terminal =
          nextStatus == TransferStatus.canceled ||
          nextStatus == TransferStatus.done ||
          nextStatus == TransferStatus.failed;
      final resolvedStatus = canceled && !terminal
          ? TransferStatus.canceled
          : nextStatus;
      if (task.status != resolvedStatus) {
        changed = true;
        shouldPersist = true;
      }
      if (terminal) _cancelRequestedIds.remove(snapshot.id);
      task.status = resolvedStatus;
      final needsPersist = _snapshotNeedsPersistence(task, snapshot);
      if (_copySnapshot(task, snapshot)) changed = true;
      _publishRemoteTask(task);
      shouldPersist = shouldPersist || needsPersist;
    }
    if (changed) {
      _rebuildMountWritebackCounts();
      if (shouldPersist) scheduleTransferQueuePersist(this);
      _scheduleNotifyListeners();
    }
    _ensurePolling();
  }

  bool _copySnapshot(TransferTask task, TransferSnapshot snapshot) {
    final changed =
        task.bytesCompleted != snapshot.bytesCompleted ||
        task.totalBytes != snapshot.totalBytes ||
        task.speedBytes != snapshot.speedBytes ||
        task.itemsCompleted != snapshot.itemsCompleted ||
        task.totalItems != snapshot.totalItems ||
        task.currentFileKey != snapshot.currentFileKey ||
        task.currentFileBytesCompleted != snapshot.currentFileBytesCompleted ||
        task.currentFileTotalBytes != snapshot.currentFileTotalBytes ||
        task.targetPath != snapshot.targetPath ||
        task.statusDetail != snapshot.statusDetail ||
        task.createdAt != snapshot.createdAt ||
        task.error != snapshot.error;
    task.bytesCompleted = snapshot.bytesCompleted;
    task.totalBytes = snapshot.totalBytes;
    task.itemsCompleted = snapshot.itemsCompleted;
    task.totalItems = snapshot.totalItems;
    task.currentFileKey = snapshot.currentFileKey;
    task.currentFileBytesCompleted = snapshot.currentFileBytesCompleted;
    task.currentFileTotalBytes = snapshot.currentFileTotalBytes;
    task.speedBytes = snapshot.speedBytes;
    task.targetPath = snapshot.targetPath;
    task.statusDetail = snapshot.statusDetail;
    task.createdAt = snapshot.createdAt;
    task.error = snapshot.error;
    return changed;
  }

  bool _snapshotNeedsPersistence(
    TransferTask task,
    TransferSnapshot snapshot,
  ) =>
      task.totalBytes != snapshot.totalBytes ||
      task.itemsCompleted != snapshot.itemsCompleted ||
      task.totalItems != snapshot.totalItems ||
      task.currentFileKey != snapshot.currentFileKey ||
      task.currentFileBytesCompleted != snapshot.currentFileBytesCompleted ||
      task.currentFileTotalBytes != snapshot.currentFileTotalBytes ||
      task.targetPath != snapshot.targetPath ||
      task.statusDetail != snapshot.statusDetail ||
      task.createdAt != snapshot.createdAt ||
      task.error != snapshot.error;
}
