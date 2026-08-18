// 全局传输状态：共享对象操作任务、轮询 Go 进度快照，并为侧边栏提供聚合速度。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/file_sync_status_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'transfer_task.dart';
part 'transfer_queue_storage.dart';
part 'transfer_queue_sync.dart';
part 'transfer_queue_metrics.dart';
part 'transfer_queue_local_progress.dart';
part 'transfer_queue_lifecycle.dart';
part 'transfer_queue_foreground.dart';
part 'transfer_queue_directory_children.dart';

/// 全局队列：页面和侧边栏共享。
class TransferQueue extends ChangeNotifier {
  TransferQueue._();

  static final TransferQueue instance = TransferQueue._();
  static const Duration _activePollInterval = Duration(milliseconds: 700);
  static const Duration _idlePollInterval = Duration(seconds: 2);
  static const Duration _notifyDebounce = Duration(milliseconds: 180);

  final List<TransferTask> _tasks = [];
  final Map<String, TransferTask> _tasksById = <String, TransferTask>{};
  final Set<String> _foregroundTaskIds = <String>{};
  final Map<String, _MountWritebackPathCounts> _mountWritebackCounts =
      <String, _MountWritebackPathCounts>{};
  RemoteStorageGateway? _api;
  Timer? _pollTimer;
  Duration? _pollInterval;
  Timer? _persistTimer;
  Timer? _notifyTimer;
  bool _polling = false;
  int _seed = 0;
  final Set<String> _cancelRequestedIds = <String>{};
  Future<void>? _restoreFuture;

  List<TransferTask> get tasks => List.unmodifiable(_tasks);
  Iterable<TransferTask> get taskView => _tasks;
  bool get hasRunning => _tasks.any((task) => task.isRunning || task.isPending);

  /// True while a normal upload/download is pending or running (blocks app update).
  bool get hasActiveFileTransfers =>
      _tasks.any((task) => task.isActiveFileTransfer);
  int get runningCount =>
      _tasks.where((task) => task.isRunning || task.isPending).length;

  bool canCancelTask(String id) => _canCancelTask(_taskById(id));

  /// Reports whether a task can be removed from the queue (i.e. it exists,
  /// has finished, and is not a managed directory child).
  bool canRemoveTask(String id) {
    final task = _taskById(id);
    return task != null && _canRemoveTask(task);
  }

  int cancelableTaskCount(Iterable<String> ids) =>
      _countTasks(ids, _canCancelTask);

  /// Number of selected tasks that can be removed from the history list.
  int removableTaskCount(Iterable<String> ids) =>
      _countTasks(ids, (task) => task != null && _canRemoveTask(task));

  bool canTriggerTask(String id) => _canTriggerTask(_taskById(id));

  int triggerableTaskCount(Iterable<String> ids) =>
      _countTasks(ids, _canTriggerTask);

  Future<void> cancelTask(String id) async {
    final existingTask = _taskById(id);
    if (!_canCancelTask(existingTask)) return;
    final task = existingTask!;
    _cancelRequestedIds.add(id);
    task.status = TransferStatus.canceled;
    task.speedBytes = 0;
    task.error = null;
    _rebuildMountWritebackCounts();
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    if (_api != null) {
      await _api!.cancelTransfer(id);
    }
    await _cancelDirectoryChildTasks(id);
    _ensurePolling();
  }

  Future<int> cancelTasks(Iterable<String> ids) async {
    final cancellations = <Future<void>>[];
    var canceled = 0;
    for (final id in ids.toSet()) {
      final task = _taskById(id);
      if (!_canCancelTask(task)) {
        continue;
      }
      cancellations.add(cancelTask(id));
      canceled++;
    }
    await Future.wait(cancellations);
    return canceled;
  }

  Future<bool> triggerTaskNow(String id) async {
    final existingTask = _taskById(id);
    if (!_canTriggerTask(existingTask)) {
      return false;
    }
    final triggered = await _api!.triggerTransfer(id);
    await pollNow();
    return triggered;
  }

  Future<int> triggerTasksNow(Iterable<String> ids) async {
    if (_api == null) {
      return 0;
    }
    var triggeredCount = 0;
    for (final id in ids.toSet()) {
      final task = _taskById(id);
      if (!_canTriggerTask(task)) {
        continue;
      }
      final triggered = await _api!.triggerTransfer(id);
      if (triggered) {
        triggeredCount++;
      }
    }
    await pollNow();
    return triggeredCount;
  }

  bool isCancelRequested(String id) => _cancelRequestedIds.contains(id);

  /// Removes a single finished task from the queue. Returns true when a task
  /// was actually removed. Active (pending/running) tasks cannot be removed —
  /// callers should cancel them first.
  bool removeTask(String id) {
    final task = _tasksById[id];
    if (task == null) {
      return false;
    }
    if (!_canRemoveTask(task)) {
      return false;
    }
    _tasks.removeWhere((t) => t.id == id);
    _tasksById.remove(id);
    _foregroundTaskIds.remove(id);
    _cancelRequestedIds.remove(id);
    _rebuildMountWritebackCounts();
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    return true;
  }

  /// Removes the given selection of finished tasks. Returns the number of
  /// entries actually purged. Active or directory-child tasks are skipped.
  int removeTasks(Iterable<String> ids) {
    var removed = 0;
    for (final id in ids.toSet()) {
      if (removeTask(id)) {
        removed++;
      }
    }
    return removed;
  }

  /// Removes every finished task (done / failed / canceled). Returns how many
  /// entries were purged. Used by the toolbar "清空已完成" action.
  int clearFinished() {
    final before = _tasks.length;
    _tasks.removeWhere(_canRemoveTask);
    if (_tasks.length == before) {
      return 0;
    }
    final remainingIds = _tasks.map((task) => task.id).toSet();
    _tasksById.removeWhere((id, _) => !remainingIds.contains(id));
    _foregroundTaskIds.removeWhere((id) => !remainingIds.contains(id));
    _cancelRequestedIds.removeWhere((id) => !remainingIds.contains(id));
    _rebuildMountWritebackCounts();
    scheduleTransferQueuePersist(this);
    _scheduleNotifyListeners();
    return before - _tasks.length;
  }

  bool _canRemoveTask(TransferTask task) {
    if (task.isDirectoryChild) {
      // Directory upload children are managed by their parent task; do not let
      // users delete them individually to avoid dangling parent references.
      return false;
    }
    return task.isFinished;
  }

  TransferStatus? statusOf(String id) => _taskById(id)?.status;

  TransferTask? findActiveTask({
    required TransferKind kind,
    required String bucket,
    required String key,
    required String localPath,
    String targetPath = '',
  }) {
    for (final task in _tasks) {
      if (task.kind != kind) continue;
      if (task.bucket != bucket || task.key != key) continue;
      if (task.localPath != localPath) continue;
      if (task.targetPath != targetPath) continue;
      if (!task.isFinished) {
        return task;
      }
    }
    return null;
  }

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
      final resolvedStatus =
          _cancelRequestedIds.contains(snapshot.id) &&
              nextStatus != TransferStatus.canceled &&
              nextStatus != TransferStatus.done &&
              nextStatus != TransferStatus.failed
          ? TransferStatus.canceled
          : nextStatus;
      if (task.status != resolvedStatus) {
        changed = true;
        shouldPersist = true;
      }
      if (_cancelRequestedIds.contains(snapshot.id) &&
          nextStatus != TransferStatus.canceled &&
          nextStatus != TransferStatus.done &&
          nextStatus != TransferStatus.failed) {
        task.status = TransferStatus.canceled;
      } else {
        if (nextStatus == TransferStatus.canceled ||
            nextStatus == TransferStatus.done ||
            nextStatus == TransferStatus.failed) {
          _cancelRequestedIds.remove(snapshot.id);
        }
        task.status = nextStatus;
      }
      if (task.bytesCompleted != snapshot.bytesCompleted ||
          task.totalBytes != snapshot.totalBytes ||
          task.speedBytes != snapshot.speedBytes ||
          task.itemsCompleted != snapshot.itemsCompleted ||
          task.totalItems != snapshot.totalItems ||
          task.currentFileKey != snapshot.currentFileKey ||
          task.currentFileBytesCompleted !=
              snapshot.currentFileBytesCompleted ||
          task.currentFileTotalBytes != snapshot.currentFileTotalBytes ||
          task.targetPath != snapshot.targetPath ||
          task.statusDetail != snapshot.statusDetail ||
          task.createdAt != snapshot.createdAt ||
          task.error != snapshot.error) {
        changed = true;
      }
      if (task.totalBytes != snapshot.totalBytes ||
          task.itemsCompleted != snapshot.itemsCompleted ||
          task.totalItems != snapshot.totalItems ||
          task.currentFileKey != snapshot.currentFileKey ||
          task.currentFileBytesCompleted !=
              snapshot.currentFileBytesCompleted ||
          task.currentFileTotalBytes != snapshot.currentFileTotalBytes ||
          task.targetPath != snapshot.targetPath ||
          task.statusDetail != snapshot.statusDetail ||
          task.createdAt != snapshot.createdAt ||
          task.error != snapshot.error) {
        shouldPersist = true;
      }
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
    }
    if (changed) {
      _rebuildMountWritebackCounts();
      if (shouldPersist) {
        scheduleTransferQueuePersist(this);
      }
      _scheduleNotifyListeners();
    }
    _ensurePolling();
  }

  List<TransferTask> recentTasks({int limit = 6}) {
    if (limit <= 0 || _tasks.isEmpty) {
      return const <TransferTask>[];
    }
    final end = limit < _tasks.length ? limit : _tasks.length;
    return _tasks.sublist(0, end);
  }

  @visibleForTesting
  void resetForTest() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInterval = null;
    _persistTimer?.cancel();
    _persistTimer = null;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _polling = false;
    _seed = 0;
    _api = null;
    _restoreFuture = null;
    _tasks.clear();
    _tasksById.clear();
    _foregroundTaskIds.clear();
    _mountWritebackCounts.clear();
    _cancelRequestedIds.clear();
    notifyListeners();
  }

  @visibleForTesting
  Future<void> restorePersistedStateForTest() =>
      restorePersistedTransferQueueState(this);

  @visibleForTesting
  Future<void> flushPersistenceForTest() => persistTransferQueueState(this);

  Future<void> pollNow() async {
    if (_api == null || _polling) return;
    _polling = true;
    try {
      final snapshots = await _api!.listTransferJobs();
      refreshFromSnapshots(snapshots);
    } finally {
      _polling = false;
    }
  }

  void _ensurePolling() {
    if (_api == null) return;
    final nextInterval = hasRunning ? _activePollInterval : _idlePollInterval;
    if (_pollTimer != null && _pollInterval == nextInterval) {
      return;
    }
    _pollTimer?.cancel();
    _pollInterval = nextInterval;
    _pollTimer = Timer.periodic(nextInterval, (_) => unawaited(pollNow()));
  }

  TransferTask? _taskById(String id) {
    return _tasksById[id];
  }

  bool _canCancelTask(TransferTask? task) => task?.isCancelable ?? false;

  bool _canTriggerTask(TransferTask? task) =>
      _api != null &&
      task != null &&
      task.status == TransferStatus.pending &&
      task.isUpload &&
      (!task.isMountWriteback || task.isSyncWaiting);

  int _countTasks(
    Iterable<String> ids,
    bool Function(TransferTask? task) predicate,
  ) {
    var count = 0;
    for (final id in ids.toSet()) {
      if (predicate(_taskById(id))) {
        count++;
      }
    }
    return count;
  }

  TransferTask _addRemoteTask(TransferSnapshot snapshot) {
    final task = TransferTask(
      id: snapshot.id,
      kind: _kindFromWire(snapshot.type),
      rawType: snapshot.type,
      bucket: snapshot.bucket,
      key: snapshot.key,
      localPath: snapshot.localPath,
      targetPath: snapshot.targetPath,
    );
    task.statusDetail = snapshot.statusDetail;
    task.createdAt = snapshot.createdAt;
    task.itemsCompleted = snapshot.itemsCompleted;
    task.totalItems = snapshot.totalItems;
    task.currentFileKey = snapshot.currentFileKey;
    task.currentFileBytesCompleted = snapshot.currentFileBytesCompleted;
    task.currentFileTotalBytes = snapshot.currentFileTotalBytes;
    _tasks.insert(0, task);
    _tasksById[task.id] = task;
    return task;
  }

  Future<void> _restorePersistedTasks() async {
    await loadPersistedTransferQueueStateData(this);
    if (_tasks.isNotEmpty) {
      _rebuildMountWritebackCounts();
      scheduleTransferQueuePersist(this);
      _scheduleNotifyListeners();
    }
  }

  void _scheduleNotifyListeners() {
    _notifyTimer?.cancel();
    _notifyTimer = Timer(_notifyDebounce, notifyListeners);
  }

  void _rebuildMountWritebackCounts() {
    _mountWritebackCounts.clear();
    for (final task in _tasks) {
      if (!task.id.startsWith('mount-writeback-')) {
        continue;
      }
      if (!task.isUpload) {
        continue;
      }
      if (task.status != TransferStatus.pending &&
          task.status != TransferStatus.running) {
        continue;
      }
      final bucket = task.bucket.trim();
      final key = task.key.trim();
      if (bucket.isEmpty || key.isEmpty) {
        continue;
      }
      final counts = _mountWritebackCounts.putIfAbsent(
        '$bucket\n$key',
        () => _MountWritebackPathCounts(),
      );
      switch (task.status) {
        case TransferStatus.pending:
          counts.pending++;
        case TransferStatus.running:
          counts.running++;
        case TransferStatus.done:
        case TransferStatus.failed:
        case TransferStatus.canceled:
          break;
      }
    }
  }

  TransferKind _kindFromWire(String value) {
    switch (value) {
      case 'download':
        return TransferKind.download;
      case 'copy':
        return TransferKind.copy;
      case 'move':
        return TransferKind.move;
      case 'delete':
        return TransferKind.delete;
      case 'app_update':
        return TransferKind.appUpdate;
      default:
        return TransferKind.upload;
    }
  }

  TransferStatus _statusFromWire(String value) {
    switch (value) {
      case 'running':
        return TransferStatus.running;
      case 'done':
        return TransferStatus.done;
      case 'failed':
        return TransferStatus.failed;
      case 'canceled':
        return TransferStatus.canceled;
      default:
        return TransferStatus.pending;
    }
  }
}
