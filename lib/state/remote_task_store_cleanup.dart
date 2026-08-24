// History cleanup: removes terminal rows from the Go projection and local
// producer caches, then refreshes the active-only view. Part of the store.
part of 'remote_task_store.dart';

/// Shared implementation for RemoteTaskStore.clearHistory; kept here so the
/// main store file stays under the repository's 500-line cap.
Future<int> clearRemoteTaskHistory(
  RemoteTaskStore store, {
  String profileId = '',
  String bucket = '',
  List<String> taskIds = const <String>[],
}) async {
  var removed = 0;
  if (store._api != null) {
    removed = await store._api!.clearRemoteTaskHistory(
      profileId: profileId,
      bucket: bucket,
      taskIds: taskIds,
    );
    if (taskIds.isEmpty) {
      store._tasks.removeWhere(
        (id, task) =>
            isRemoteTaskHistory(task) &&
            (profileId.isEmpty || task.profileId == profileId) &&
            (bucket.isEmpty || task.bucket == bucket),
      );
    } else {
      final selected = taskIds.toSet();
      store._tasks.removeWhere(
        (id, task) => selected.contains(id) && isRemoteTaskHistory(task),
      );
    }
    store.notifyListenersChanged();
    // Refresh active-only after cleanup: pulling a fresh history page here
    // is what made "clear 100, then 100 more appear" feel endless. The
    // remaining history stays behind 加载更多历史 until the user asks for it.
    await store.pollActive();
  }
  if (taskIds.isEmpty) {
    removed +=
        store._clearLocalTaskHistory?.call() ??
        store._removeLocalTerminalTasks();
    removed += store._removeExecutionTerminalTasks();
  } else {
    removed += store._removeLocalTerminalTasksById(taskIds);
    removed += store._removeExecutionTasksById(taskIds);
  }
  return removed;
}
