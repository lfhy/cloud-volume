// 任务队列持久化：将最近任务快照存到 SharedPreferences，并在重启后恢复。

part of 'transfer_queue.dart';

const Duration _persistDebounce = Duration(milliseconds: 400);
const String _storageKey = 'transfer_queue.tasks.v2';
const String _legacyStorageKey = 'transfer_queue.tasks.v1';
const int _persistedTaskLimit = 200;

Future<void> restorePersistedTransferQueueState(TransferQueue queue) {
  return queue._restoreFuture ??= queue._restorePersistedTasks();
}

Future<void> persistTransferQueueState(TransferQueue queue) async {
  queue._persistTimer?.cancel();
  queue._persistTimer = null;
  final prefs = await SharedPreferences.getInstance();
  // Terminal local producer rows belong to Go's remote-task history, not this
  // execution facade. Persist only a live hand-off; restart will discard it
  // safely because Dart cannot resume a producer closure after process exit.
  final payload = queue._tasks
      .where((task) => task.publishRemoteTask && !task.isFinished)
      .take(_persistedTaskLimit)
      .map((task) => task.toJson())
      .toList(growable: false);
  await prefs.setString(_storageKey, jsonEncode(payload));
}

void scheduleTransferQueuePersist(TransferQueue queue) {
  queue._persistTimer?.cancel();
  queue._persistTimer = Timer(
    _persistDebounce,
    () => unawaited(persistTransferQueueState(queue)),
  );
}

Future<void> loadPersistedTransferQueueStateData(TransferQueue queue) async {
  if (queue._tasks.isNotEmpty) {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_storageKey);
  // v1 rows predate the producer ownership bit and are never safe to keep.
  await prefs.remove(_legacyStorageKey);
  if (raw == null || raw.isEmpty) {
    return;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      await prefs.remove(_storageKey);
      return;
    }
    // A Dart producer cannot survive restart. Its terminal result is either
    // already represented by Go's unified history or unavailable, so retaining
    // any old local payload would create task-page rows with no backend peer.
    queue._tasks.clear();
    queue._tasksById.clear();
    // Remove old persisted terminal payloads written by previous versions.
    await prefs.remove(_storageKey);
  } catch (_) {
    await prefs.remove(_storageKey);
    queue._tasks.clear();
    queue._tasksById.clear();
    return;
  }
}
