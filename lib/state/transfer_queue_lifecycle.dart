part of 'transfer_queue.dart';

// Task lifecycle operations own queue creation and terminal state transitions.
extension TransferQueueLifecycle on TransferQueue {
  void bindApi(RemoteStorageGateway api) {
    _api = api;
    RemoteTaskStore.instance.bindApi(api);
    unawaited(restorePersistedTransferQueueState(this).then((_) => pollNow()));
    _ensurePolling();
  }

  TransferTask startTask({
    String? id,
    required TransferKind kind,
    required String bucket,
    required String key,
    required String localPath,
    String targetPath = '',
  }) {
    if (id != null && _tasksById.containsKey(id)) {
      return _tasksById[id]!;
    }
    final task = TransferTask(
      id: id ?? 'transfer_${DateTime.now().microsecondsSinceEpoch}_${_seed++}',
      kind: kind,
      bucket: bucket,
      key: key,
      localPath: localPath,
      targetPath: targetPath,
    );
    _tasks.insert(0, task);
    _tasksById[task.id] = task;
    _rebuildMountWritebackCounts();
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    _ensurePolling();
    return task;
  }

  void markTaskFailed(String id, Object error) {
    final task = _taskById(id);
    if (task == null) return;
    if (task.status == TransferStatus.canceled ||
        _cancelRequestedIds.remove(id)) {
      markTaskCanceled(id);
      return;
    }
    task.status = TransferStatus.failed;
    task.statusDetail = '';
    task.error = error.toString();
    task.speedBytes = 0;
    _rebuildMountWritebackCounts();
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    _ensurePolling();
  }

  void markTaskDone(String id) {
    final task = _taskById(id);
    if (task == null) return;
    _cancelRequestedIds.remove(id);
    task.status = TransferStatus.done;
    task.statusDetail = '';
    task.speedBytes = 0;
    task.bytesCompleted = task.totalBytes > 0
        ? task.totalBytes
        : task.bytesCompleted;
    task.itemsCompleted = task.totalItems > 0
        ? task.totalItems
        : task.itemsCompleted;
    _rebuildMountWritebackCounts();
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    _ensurePolling();
  }

  void markTaskCanceled(String id) {
    final task = _taskById(id);
    if (task == null) return;
    _cancelRequestedIds.remove(id);
    task.status = TransferStatus.canceled;
    task.statusDetail = '';
    task.speedBytes = 0;
    task.error = null;
    _rebuildMountWritebackCounts();
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    _ensurePolling();
  }
}
