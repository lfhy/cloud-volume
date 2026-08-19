part of 'transfer_queue.dart';

// Mirrors the legacy producer state into the unified task store for local UI.
extension TransferQueueRemoteTasks on TransferQueue {
  void _publishRemoteTask(TransferTask task) {
    _bindRemoteTaskActions();
    final id = 'transfer:${task.id}';
    RemoteTaskStore.instance.updateLocalTask(
      RemoteTask(
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
        cancelable: task.isCancelable,
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
      ),
    );
  }

  void _removeRemoteTask(String id) {
    RemoteTaskStore.instance.removeLocalTask('transfer:$id');
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
    if (!_canCancelTask(_taskById(id))) return false;
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
