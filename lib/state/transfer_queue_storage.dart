// 任务队列持久化：将最近任务快照存到 SharedPreferences，并在重启后恢复。

part of 'transfer_queue.dart';

const Duration _persistDebounce = Duration(milliseconds: 400);
const String _storageKey = 'transfer_queue.tasks.v1';
const int _persistedTaskLimit = 200;
const String _interruptedTaskMessage = '应用上次关闭前该任务未完成，请重新发起。';

Future<void> restorePersistedTransferQueueState(TransferQueue queue) {
  return queue._restoreFuture ??= queue._restorePersistedTasks();
}

Future<void> persistTransferQueueState(TransferQueue queue) async {
  queue._persistTimer?.cancel();
  queue._persistTimer = null;
  final prefs = await SharedPreferences.getInstance();
  final payload = queue._tasks
      .where((task) => task.publishRemoteTask)
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
  if (raw == null || raw.isEmpty) {
    return;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return;
    }
    queue._tasks.clear();
    queue._tasksById.clear();
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final task = TransferTask.fromJson(Map<String, dynamic>.from(item));
      if (!task.publishRemoteTask) {
        // Metadata-backed operations are durable in Go; do not resurrect an
        // obsolete Dart execution row after an app restart.
        continue;
      }
      if (task.status == TransferStatus.pending ||
          task.status == TransferStatus.running) {
        task.status = TransferStatus.failed;
        task.speedBytes = 0;
        task.error = _interruptedTaskMessage;
      }
      queue._tasks.add(task);
      queue._tasksById[task.id] = task;
    }
  } catch (_) {
    await prefs.remove(_storageKey);
    queue._tasks.clear();
    queue._tasksById.clear();
    return;
  }
}
