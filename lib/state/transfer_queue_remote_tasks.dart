part of 'transfer_queue.dart';

// Mirrors the legacy producer state into the unified task store for local UI.
extension TransferQueueRemoteTasks on TransferQueue {
  void _publishRemoteTask(TransferTask task) {
    if (!task.publishRemoteTask) {
      // A metadata-backed page mutation already has a durable sync:* task in
      // Go. Keep only an execution projection for transient progress UI.
      _bindRemoteTaskActions();
      if (task.isUpload || task.isDelete) {
        RemoteTaskStore.instance.publishExecutionTask(
          _remoteTaskSnapshot(task),
        );
      } else {
        RemoteTaskStore.instance.removeExecutionTask('transfer:${task.id}');
      }
      return;
    }
    _bindRemoteTaskActions();
    // Terminal producer rows are not durable task history. Go's runtime or
    // metadata projection owns visible history; retaining this Dart row caused
    // "history 200" while the backend truth and queue counts were both zero.
    if (task.isFinished) {
      // The progress dialog still needs the final snapshot until the user
      // closes it, but that transient result must not re-enter the task page.
      RemoteTaskStore.instance.publishExecutionTask(_remoteTaskSnapshot(task));
      RemoteTaskStore.instance.removeLocalTask('transfer:${task.id}');
      return;
    }
    RemoteTaskStore.instance.removeExecutionTask('transfer:${task.id}');
    RemoteTaskStore.instance.updateLocalTask(_remoteTaskSnapshot(task));
  }

  RemoteTask _remoteTaskSnapshot(TransferTask task) {
    final id = 'transfer:${task.id}';
    return RemoteTask(
      id: id,
      kind: _remoteKind(task.kind),
      status: _remoteStatus(task.status),
      source: task.isAppUpdate
          ? RemoteTaskSource.appUpdate
          : task.isSyncTask
          ? RemoteTaskSource.sync
          : RemoteTaskSource.local,
      bucket: task.bucket,
      sourcePath: task.key,
      targetPath: task.targetPath,
      localPath: task.localPath,
      displayPath: task.key,
      phase: _remotePhase(task.statusDetail),
      phaseDetail: task.statusDetail,
      error: task.error ?? '',
      createdAt: task.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      retryCount: 0,
      // Local producers retain their execution closure rather than a
      // replayable request payload, so only cancellation/trigger is safe.
      retryable: false,
      triggerable: task.canForceSyncNow,
      progress: RemoteTaskProgress(
        bytesCompleted: task.bytesCompleted,
        totalBytes: task.totalBytes,
        itemsCompleted: task.itemsCompleted,
        totalItems: task.totalItems,
        speedBytes: task.speedBytes,
        currentKey: task.currentFileKey,
      ),
      // Metadata-backed page mutations are already controlled by the Go
      // journal; this compatibility snapshot must never offer a fake cancel.
      cancelable: task.publishRemoteTask && task.isCancelable,
    );
  }

  void _removeRemoteTask(String id) {
    RemoteTaskStore.instance.removeLocalTask('transfer:$id');
    RemoteTaskStore.instance.removeExecutionTask('transfer:$id');
  }

  void _bindRemoteTaskActions() {
    RemoteTaskStore.instance.bindLocalTaskActions(
      cancel: _cancelRemoteTask,
      trigger: _triggerRemoteTask,
      clearHistory: clearFinished,
    );
  }

  Future<bool> _cancelRemoteTask(String taskId) async {
    final id = taskId.replaceFirst('transfer:', '');
    final task = _taskById(id);
    if (task == null || !task.publishRemoteTask || !_canCancelTask(task)) {
      return false;
    }
    await cancelTask(id);
    return true;
  }

  Future<bool> _triggerRemoteTask(String taskId) {
    final id = taskId.replaceFirst('transfer:', '');
    return triggerTaskNow(id);
  }

  RemoteTaskKind _remoteKind(TransferKind kind) => switch (kind) {
    TransferKind.upload => RemoteTaskKind.upload,
    TransferKind.download => RemoteTaskKind.download,
    TransferKind.copy => RemoteTaskKind.copy,
    TransferKind.move => RemoteTaskKind.move,
    TransferKind.delete => RemoteTaskKind.delete,
    TransferKind.appUpdate => RemoteTaskKind.appUpdate,
  };

  RemoteTaskStatus _remoteStatus(TransferStatus status) => switch (status) {
    TransferStatus.pending => RemoteTaskStatus.waiting,
    TransferStatus.running => RemoteTaskStatus.running,
    TransferStatus.done => RemoteTaskStatus.done,
    TransferStatus.failed => RemoteTaskStatus.failed,
    TransferStatus.canceled => RemoteTaskStatus.canceled,
  };

  RemoteTaskPhase _remotePhase(String detail) => switch (detail) {
    'selecting_path' || 'scanning' => RemoteTaskPhase.local,
    'verifying' => RemoteTaskPhase.verification,
    'cleanup' => RemoteTaskPhase.cleanup,
    _ => RemoteTaskPhase.local,
  };
}
