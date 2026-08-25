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
  final api = store._api;
  final generation = store._bindingGeneration;
  if (api != null) {
    removed = await api.clearRemoteTaskHistory(
      profileId: profileId,
      bucket: bucket,
      taskIds: taskIds,
    );
    // A late clear from an old profile must not erase the newly bound API's
    // rows or pagination state. The backend operation may have succeeded, but
    // it no longer belongs to this visible store binding.
    if (generation != store._bindingGeneration || !identical(api, store._api)) {
      return 0;
    }
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
    // History deletion changes the ordered stream. Its old cursor can point
    // past rows that shifted or were removed, so never reuse it for a later
    // manual page request.
    store._historyEpoch++;
    store._nextCursor = '';
    store._hasLoadedMore = false;
    store.notifyListenersChanged();
    // Refresh active-only after cleanup: pulling a fresh history page here
    // is what made "clear 100, then 100 more appear" feel endless. The
    // remaining history stays behind 加载更多历史 until the user asks for it.
    final preClearRead = store._inFlightRead;
    if (preClearRead != null) await preClearRead;
    if (generation != store._bindingGeneration || !identical(api, store._api)) {
      return 0;
    }
    await store.pollActive();
    if (generation != store._bindingGeneration || !identical(api, store._api)) {
      return 0;
    }
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
