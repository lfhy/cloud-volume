// Snapshot reconciliation: merges one remote-task page into the unified
// cache map, purging rows the server no longer reports (complete snapshot,
// active-only poll, or stale physical metadata projections).
part of 'remote_task_store.dart';

extension RemoteTaskStoreMergeLifecycle on RemoteTaskStore {
  /// True when a first history request or a later cursor can reveal rows that
  /// active-only polling intentionally left out of the list cache.
  bool get canLoadMoreHistory {
    if (_api == null) return false;
    if (_nextCursor.isNotEmpty) return true;
    if (_hasLoadedMore) return false;
    final loadedHistory = _tasks.values.where(isRemoteTaskHistory).length;
    if (_queue.reported) return _queue.history > loadedHistory;
    if (_hasServerTotal) return _total > _tasks.length;
    // Older bridge versions omitted both fields. Permit one explicit history
    // request, then let its exhausted cursor close the affordance.
    return true;
  }

  /// Reconciles one server page into the cache without exposing raw maps.
  void _mergeRemoteTasks(
    Iterable<RemoteTask> incoming, {
    bool completeSnapshot = false,
    bool purgeMissingActive = false,
    bool purgeAllWhenExplicitlyEmpty = false,
  }) {
    mergeRemoteTaskPage(
      tasks: _tasks,
      incoming: incoming,
      completeSnapshot: completeSnapshot,
      purgeMissingActive: purgeMissingActive,
      purgeAllWhenExplicitlyEmpty: purgeAllWhenExplicitlyEmpty,
      onChanged: notifyListenersChanged,
    );
  }
}

/// True only for Go rows that may be cleared as retained task history.
bool isRemoteTaskHistory(RemoteTask task) =>
    task.status == RemoteTaskStatus.done ||
    task.status == RemoteTaskStatus.canceled;

// The active-only bridge response includes failures/conflicts so users can
// retry them. Only done/canceled rows are absent from that response.
bool isRemoteTaskUnsettled(RemoteTask task) => !isRemoteTaskHistory(task);

/// Applies one page merge to [tasks]; [onChanged] fires once if anything
/// actually changed so listeners rebuild without redundant notifications.
void mergeRemoteTaskPage({
  required Map<String, RemoteTask> tasks,
  required Iterable<RemoteTask> incoming,
  bool completeSnapshot = false,
  bool purgeMissingActive = false,
  bool purgeAllWhenExplicitlyEmpty = false,
  required void Function() onChanged,
}) {
  final incomingList = incoming.toList(growable: false);
  final incomingIds = incomingList.map((task) => task.id).toSet();
  var changed = false;
  // Metadata physical snapshots were removed from the bridge projection in
  // a later protocol revision. Purge them here too so a running app cannot
  // keep displaying rows fetched by an older bridge binary.
  final stalePhysicalIds = tasks.keys
      .where(
        (id) =>
            id.startsWith('transfer:metadata-op-') && !incomingIds.contains(id),
      )
      .toList(growable: false);
  for (final id in stalePhysicalIds) {
    tasks.remove(id);
    changed = true;
  }
  if (purgeAllWhenExplicitlyEmpty) {
    // An active-only page normally says nothing about cached history. The
    // explicit full-set total of zero is the exception: no server row can
    // still exist, so retaining a previously loaded history is stale UI.
    if (tasks.isNotEmpty) {
      tasks.clear();
      changed = true;
    }
  } else if (completeSnapshot) {
    final staleIds = tasks.keys
        .where((id) => !incomingIds.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      tasks.remove(id);
      changed = true;
    }
  } else if (purgeMissingActive) {
    // Active-only poll: drop cached rows the server no longer reports as
    // unsettled. They completed between polls; retaining them froze the
    // "进行中/等待中" counts on screen.
    final goneActiveIds = tasks.entries
        .where(
          (entry) =>
              isRemoteTaskUnsettled(entry.value) &&
              !incomingIds.contains(entry.key),
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in goneActiveIds) {
      tasks.remove(id);
      changed = true;
    }
  }
  for (final task in incomingList) {
    if (tasks[task.id] != task) changed = true;
    tasks[task.id] = task;
  }
  if (changed) onChanged();
}

/// Drops every terminal row from [tasks]; returns how many were removed.
int removeTerminalTasks({
  required Map<String, RemoteTask> tasks,
  required void Function() onChanged,
}) {
  final ids = tasks.entries
      .where((entry) => !entry.value.status.isActive)
      .map((entry) => entry.key)
      .toList(growable: false);
  for (final id in ids) {
    tasks.remove(id);
  }
  if (ids.isNotEmpty) onChanged();
  return ids.length;
}

/// Drops selected terminal rows from [tasks]; returns how many were removed.
int removeTerminalTasksById({
  required Map<String, RemoteTask> tasks,
  required Iterable<String> taskIds,
  required void Function() onChanged,
}) {
  final selected = taskIds.toSet();
  final ids = tasks.entries
      .where(
        (entry) => selected.contains(entry.key) && !entry.value.status.isActive,
      )
      .map((entry) => entry.key)
      .toList(growable: false);
  for (final id in ids) {
    tasks.remove(id);
  }
  if (ids.isNotEmpty) onChanged();
  return ids.length;
}
