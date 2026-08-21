// Remote task store polls the unified Go projection; legacy producers never
// become a display fallback when the remote-task endpoint is unavailable.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

typedef LocalRemoteTaskAction = Future<bool> Function(String taskId);
typedef ClearLocalRemoteTaskHistory = int Function();

class RemoteTaskStore extends ChangeNotifier {
  RemoteTaskStore._();

  static final RemoteTaskStore instance = RemoteTaskStore._();
  static const _activePollInterval = Duration(milliseconds: 700);
  static const _idlePollInterval = Duration(seconds: 2);

  final Map<String, RemoteTask> _tasks = <String, RemoteTask>{};
  // Local producers publish here until a durable/runtime snapshot supersedes them.
  final Map<String, RemoteTask> _localTasks = <String, RemoteTask>{};
  // Execution-only projections are used by transient progress dialogs. They
  // deliberately stay out of [tasks], which is the unified remote-task list.
  final Map<String, RemoteTask> _executionTasks = <String, RemoteTask>{};
  LocalRemoteTaskAction? _cancelLocalTask;
  LocalRemoteTaskAction? _retryLocalTask;
  LocalRemoteTaskAction? _triggerLocalTask;
  ClearLocalRemoteTaskHistory? _clearLocalTaskHistory;
  RemoteStorageGateway? _api;
  Timer? _pollTimer;
  bool _polling = false;
  Duration? _pollInterval;
  Object? _lastError;
  DateTime? _lastFreshAt;
  String _freshness = '';
  Map<String, bool> _capabilities = const <String, bool>{};
  String _nextCursor = '';
  bool _hasLoadedMore = false;
  int _bindingGeneration = 0;

  List<RemoteTask> get tasks {
    // A live Go snapshot wins; an active local producer wins over an older
    // terminal snapshot that was retained by the runtime monitor.
    final merged = <String, RemoteTask>{..._localTasks};
    for (final entry in _tasks.entries) {
      final local = merged[entry.key];
      if (local == null || !_preferLocal(local, entry.value)) {
        merged[entry.key] = entry.value;
      }
    }
    final result = merged.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return result;
  }

  bool get hasActive => tasks.any((task) => task.status.isActive);
  bool get hasActiveFileTransfers =>
      tasks.any(
        (task) =>
            task.status.isActive &&
            task.source != RemoteTaskSource.appUpdate &&
            (task.kind == RemoteTaskKind.upload ||
                task.kind == RemoteTaskKind.write ||
                task.kind == RemoteTaskKind.download),
      ) ||
      _executionTasks.values.any(
        (task) =>
            task.status.isActive &&
            task.source != RemoteTaskSource.appUpdate &&
            (task.kind == RemoteTaskKind.upload ||
                task.kind == RemoteTaskKind.write ||
                task.kind == RemoteTaskKind.download),
      );
  Object? get lastError => _lastError;
  DateTime? get lastFreshAt => _lastFreshAt;
  String get freshness => _freshness;
  Map<String, bool> get capabilities => _capabilities;
  String get nextCursor => _nextCursor;
  bool get isRefreshing => _polling;

  List<RemoteTask> tasksForProfile(String profileId) => tasks
      .where((task) => task.profileId == profileId)
      .toList(growable: false);

  /// Publishes a Dart-owned task without making it part of the remote cache.
  void publishLocalTask(RemoteTask task) {
    if (task.id.trim().isEmpty) return;
    _localTasks[task.id] = task;
    notifyListeners();
  }

  /// Replaces one local task snapshot as a producer advances its lifecycle.
  void updateLocalTask(RemoteTask task) => publishLocalTask(task);

  /// Removes a local task after its producer no longer needs history locally.
  bool removeLocalTask(String id) {
    final removed = _localTasks.remove(id) != null;
    if (removed) notifyListeners();
    return removed;
  }

  RemoteTask? localTask(String id) => _localTasks[id];

  /// Returns an execution-only snapshot for transient UI such as the upload
  /// dialog without exposing it in the durable remote task list.
  RemoteTask? executionTask(String id) => _executionTasks[id];

  void publishExecutionTask(RemoteTask task) {
    if (task.id.trim().isEmpty) return;
    _executionTasks[task.id] = task;
    notifyListeners();
  }

  bool removeExecutionTask(String id) {
    final removed = _executionTasks.remove(id) != null;
    if (removed) notifyListeners();
    return removed;
  }

  void bindLocalTaskActions({
    LocalRemoteTaskAction? cancel,
    LocalRemoteTaskAction? retry,
    LocalRemoteTaskAction? trigger,
    ClearLocalRemoteTaskHistory? clearHistory,
  }) {
    _cancelLocalTask = cancel;
    _retryLocalTask = retry;
    _triggerLocalTask = trigger;
    _clearLocalTaskHistory = clearHistory;
  }

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
    notifyListeners();
    return true;
  }

  // Active-only poll keeps every unsettled task on page one; history is only
  // fetched by explicit loadMore requests.
  Future<void> pollActive() {
    return refresh(const RemoteTaskFilter(includeHistory: false));
  }

  void bindApi(RemoteStorageGateway api) {
    if (identical(_api, api)) {
      _ensurePolling();
      if (!_polling) unawaited(pollActive());
      return;
    }
    _bindingGeneration++;
    _api = api;
    // A stale request may still complete, but its generation check prevents it
    // from mutating this binding. Clear the gate so the new endpoint starts
    // its own request immediately instead of inheriting the old in-flight one.
    _polling = false;
    _tasks.clear();
    _nextCursor = '';
    _hasLoadedMore = false;
    unawaited(pollActive());
    _ensurePolling();
  }

  Future<void> refresh([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async {
    if (_api == null || _polling) return;
    final generation = _bindingGeneration;
    final api = _api!;
    _polling = true;
    try {
      final page = await api.listRemoteTasks(filter);
      if (generation != _bindingGeneration || !identical(api, _api)) return;
      // A request without history or pagination never describes the full
      // task set, so it must not purge rows a loadMore call already merged.
      final completeSnapshot =
          filter.includeHistory && filter.cursor.isEmpty && page.nextCursor.isEmpty;
      _mergeRemoteTasks(page.items, completeSnapshot: completeSnapshot);
      // Keep the history cursor only when the response describes the history
      // stream; an active-only poll must not clear it to empty.
      if (filter.cursor.isNotEmpty || !_hasLoadedMore) {
        if (!(filter.includeHistory && page.nextCursor.isEmpty)) {
          _nextCursor = page.nextCursor;
        }
      }
      if (filter.cursor.isNotEmpty) _hasLoadedMore = true;
      _freshness = page.freshness;
      _capabilities = Map<String, bool>.unmodifiable(page.capabilities);
      _lastError = null;
      _lastFreshAt = DateTime.now();
      notifyListeners();
    } catch (error) {
      if (generation != _bindingGeneration) return;
      _lastError = error;
      // Keep the last known remote projection for continuity, but never copy
      // TransferQueue entries into it.
      notifyListeners();
    } finally {
      if (generation == _bindingGeneration) {
        _polling = false;
        _ensurePolling();
      }
    }
  }

  Future<bool> cancel(String id) async {
    final local = _localTasks[id];
    final execution = _executionTasks[id];
    final remote = _tasks[id];
    if (local != null &&
        (remote == null || _preferLocal(local, remote)) &&
        local.cancelable) {
      return _cancelLocalTask?.call(id) ?? false;
    }
    if (execution != null && remote == null && execution.cancelable) {
      return _cancelLocalTask?.call(id) ?? false;
    }
    final task = remote;
    if (task == null || !task.cancelable || _api == null) return false;
    _tasks[id] = task.copyWith(
      status: RemoteTaskStatus.cancelRequested,
      optimisticCancel: true,
    );
    notifyListeners();
    try {
      final canceled = await _api!.cancelRemoteTask(id);
      if (!canceled) {
        _tasks[id] = task;
        notifyListeners();
      }
      return canceled;
    } catch (_) {
      _tasks[id] = task;
      notifyListeners();
      rethrow;
    }
  }

  Future<RemoteTask?> loadDetails(String id) async {
    final local = _localTasks[id];
    final execution = _executionTasks[id];
    final remote = _tasks[id];
    if (_api == null ||
        (local != null && (remote == null || _preferLocal(local, remote))) ||
        (execution != null && remote == null)) {
      return local ?? execution ?? remote;
    }
    try {
      final task = await _api!.getRemoteTask(id);
      _tasks[id] = task;
      notifyListeners();
      return task;
    } catch (_) {
      return _tasks[id];
    }
  }

  Future<void> loadMore() async {
    if (_api == null || _polling) return;
    // An active-only poll leaves no cursor even when history exists, so the
    // first history request starts from page one explicitly.
    if (_nextCursor.isEmpty && _hasLoadedMore) return;
    await refresh(
      RemoteTaskFilter(cursor: _nextCursor, includeHistory: true),
    );
    _hasLoadedMore = true;
  }

  Future<bool> retry(String id) async {
    final local = _localTasks[id];
    final execution = _executionTasks[id];
    final remote = _tasks[id];
    if (local != null && (remote == null || _preferLocal(local, remote))) {
      return _retryLocalTask?.call(id) ?? false;
    }
    if (execution != null && remote == null) {
      return _retryLocalTask?.call(id) ?? false;
    }
    if (_api == null) return false;
    final result = await _api!.retryRemoteTask(id);
    await refresh();
    return result;
  }

  Future<bool> trigger(String id) async {
    final local = _localTasks[id];
    final execution = _executionTasks[id];
    final remote = _tasks[id];
    if (local != null && (remote == null || _preferLocal(local, remote))) {
      return _triggerLocalTask?.call(id) ?? false;
    }
    if (execution != null && remote == null) {
      return _triggerLocalTask?.call(id) ?? false;
    }
    if (_api == null) return false;
    final result = await _api!.triggerRemoteTask(id);
    await refresh();
    return result;
  }

  Future<int> clearHistory({
    String profileId = '',
    String bucket = '',
    List<String> taskIds = const <String>[],
  }) async {
    var removed = 0;
    if (_api != null) {
      removed = await _api!.clearRemoteTaskHistory(
        profileId: profileId,
        bucket: bucket,
        taskIds: taskIds,
      );
      if (taskIds.isEmpty) {
        _tasks.removeWhere(
          (id, task) =>
              !task.status.isActive &&
              (profileId.isEmpty || task.profileId == profileId) &&
              (bucket.isEmpty || task.bucket == bucket),
        );
      } else {
        final selected = taskIds.toSet();
        _tasks.removeWhere(
          (id, task) => selected.contains(id) && !task.status.isActive,
        );
      }
      await refresh();
    }
    if (taskIds.isEmpty) {
      removed += _clearLocalTaskHistory?.call() ?? _removeLocalTerminalTasks();
      removed += _removeExecutionTerminalTasks();
    } else {
      removed += _removeLocalTerminalTasksById(taskIds);
      removed += _removeExecutionTasksById(taskIds);
    }
    return removed;
  }

  void _mergeRemoteTasks(
    Iterable<RemoteTask> incoming, {
    bool completeSnapshot = false,
  }) {
    final incomingList = incoming.toList(growable: false);
    final incomingIds = incomingList.map((task) => task.id).toSet();
    var changed = false;
    // Metadata physical snapshots were removed from the bridge projection in
    // a later protocol revision. Purge them here too so a running app cannot
    // keep displaying rows fetched by an older bridge binary.
    final stalePhysicalIds = _tasks.keys
        .where(
          (id) =>
              id.startsWith('transfer:metadata-op-') &&
              !incomingIds.contains(id),
        )
        .toList(growable: false);
    for (final id in stalePhysicalIds) {
      _tasks.remove(id);
      changed = true;
    }
    if (completeSnapshot) {
      final staleIds = _tasks.keys
          .where((id) => !incomingIds.contains(id))
          .toList(growable: false);
      for (final id in staleIds) {
        _tasks.remove(id);
        changed = true;
      }
    }
    for (final task in incomingList) {
      if (_tasks[task.id] != task) changed = true;
      _tasks[task.id] = task;
    }
    if (changed) notifyListeners();
  }

  int _removeLocalTerminalTasks() {
    final ids = _localTasks.entries
        .where((entry) => !entry.value.status.isActive)
        .map((entry) => entry.key)
        .toList();
    for (final id in ids) {
      _localTasks.remove(id);
    }
    if (ids.isNotEmpty) notifyListeners();
    return ids.length;
  }

  int _removeLocalTerminalTasksById(Iterable<String> taskIds) {
    final selected = taskIds.toSet();
    final ids = _localTasks.entries
        .where(
          (entry) =>
              selected.contains(entry.key) && !entry.value.status.isActive,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in ids) {
      _localTasks.remove(id);
    }
    if (ids.isNotEmpty) notifyListeners();
    return ids.length;
  }

  int _removeExecutionTerminalTasks() {
    final ids = _executionTasks.entries
        .where((entry) => !entry.value.status.isActive)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in ids) {
      _executionTasks.remove(id);
    }
    if (ids.isNotEmpty) notifyListeners();
    return ids.length;
  }

  int _removeExecutionTasksById(Iterable<String> taskIds) {
    final selected = taskIds.toSet();
    final ids = _executionTasks.entries
        .where(
          (entry) =>
              selected.contains(entry.key) && !entry.value.status.isActive,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in ids) {
      _executionTasks.remove(id);
    }
    if (ids.isNotEmpty) notifyListeners();
    return ids.length;
  }

  bool _preferLocal(RemoteTask local, RemoteTask remote) {
    if (!local.status.isActive || remote.status.isActive) return false;
    final localAt = DateTime.tryParse(
      local.updatedAt.isNotEmpty ? local.updatedAt : local.createdAt,
    );
    final remoteAt = DateTime.tryParse(
      remote.updatedAt.isNotEmpty ? remote.updatedAt : remote.createdAt,
    );
    return localAt != null && (remoteAt == null || localAt.isAfter(remoteAt));
  }

  void _ensurePolling() {
    if (_api == null) return;
    final interval = hasActive ? _activePollInterval : _idlePollInterval;
    if (_pollTimer != null && _pollInterval == interval) return;
    _pollTimer?.cancel();
    _pollInterval = interval;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(pollActive()));
  }

  @visibleForTesting
  void resetForTest() {
    _bindingGeneration++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInterval = null;
    _api = null;
    _polling = false;
    _lastError = null;
    _lastFreshAt = null;
    _freshness = '';
    _capabilities = const <String, bool>{};
    _nextCursor = '';
    _hasLoadedMore = false;
    _tasks.clear();
    _localTasks.clear();
    _executionTasks.clear();
    _cancelLocalTask = null;
    _retryLocalTask = null;
    _triggerLocalTask = null;
    _clearLocalTaskHistory = null;
    notifyListeners();
  }
}
