// Local producer lifecycle helpers keep compatibility rows separate from the
// durable Go projection while preserving the newest active snapshot policy.
part of 'remote_task_store.dart';

extension RemoteTaskStoreLocalLifecycle on RemoteTaskStore {
  /// Marks a producer-owned task terminal while preserving its latest details.
  bool completeLocalTask(String id) =>
      _setLocalTaskStatus(id, RemoteTaskStatus.done);

  bool failLocalTask(String id) =>
      _setLocalTaskStatus(id, RemoteTaskStatus.failed);

  bool cancelLocalTask(String id) =>
      _setLocalTaskStatus(id, RemoteTaskStatus.canceled);

  bool _setLocalTaskStatus(String id, RemoteTaskStatus status) {
    final task = _localTasks[id];
    if (task == null) return false;
    _localTasks[id] = task.copyWith(
      status: status,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    notifyListenersChanged();
    return true;
  }
}

/// A local producer may supersede only an older terminal remote snapshot.
bool _preferLocalTask(RemoteTask local, RemoteTask remote) {
  if (!local.status.isActive || remote.status.isActive) return false;
  final localAt = DateTime.tryParse(
    local.updatedAt.isNotEmpty ? local.updatedAt : local.createdAt,
  );
  final remoteAt = DateTime.tryParse(
    remote.updatedAt.isNotEmpty ? remote.updatedAt : remote.createdAt,
  );
  return localAt != null && (remoteAt == null || localAt.isAfter(remoteAt));
}

/// Keeps client-side merge order aligned with the backend's parsed timestamp
/// ordering when runtime rows use local offsets and metadata rows use UTC.
int sortRemoteTasksNewestFirst(RemoteTask left, RemoteTask right) {
  final leftAt = _taskTimestamp(left);
  final rightAt = _taskTimestamp(right);
  if (leftAt == null && rightAt != null) return 1;
  if (leftAt != null && rightAt == null) return -1;
  if (leftAt != null && rightAt != null) {
    final byTime = rightAt.compareTo(leftAt);
    if (byTime != 0) return byTime;
  }
  return right.id.compareTo(left.id);
}

DateTime? _taskTimestamp(RemoteTask task) => DateTime.tryParse(
  task.updatedAt.isNotEmpty ? task.updatedAt : task.createdAt,
);
