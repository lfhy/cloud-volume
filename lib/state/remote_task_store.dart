// Remote task store polls the unified Go projection; legacy producers never
// become a display fallback when the remote-task endpoint is unavailable.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

import 'remote_task_events_web.dart'
    if (dart.library.io) 'remote_task_events.dart';

part 'remote_task_store_cleanup.dart';
part 'remote_task_store_actions.dart';
part 'remote_task_store_local.dart';
part 'remote_task_store_merge.dart';
part 'remote_task_store_polling.dart';

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
  Future<void>? _inFlightRead;
  Future<void>? _initialHistoryLoad;
  bool _loadingInitialHistory = false;
  Duration? _pollInterval;
  Object? _lastError;
  DateTime? _lastFreshAt;
  String _freshness = '';
  Map<String, bool> _capabilities = const <String, bool>{};
  String _nextCursor = '';
  int _total = 0;
  bool _hasServerTotal = false;
  bool _hasLoadedMore = false;
  int _historyEpoch = 0;
  int _bindingGeneration = 0;
  TaskEventsHandle? _events;
  RemoteTaskQueueCounts _queue = const RemoteTaskQueueCounts();

  List<RemoteTask> get tasks {
    // A live Go snapshot wins; an active local producer wins over an older
    // terminal snapshot that was retained by the runtime monitor.
    // Local producers are an execution hand-off only. They may surface while
    // a live Go/runtime snapshot is being established, but terminal local
    // history must never resurrect after the authoritative backend is empty.
    final merged = <String, RemoteTask>{
      for (final entry in _localTasks.entries)
        if (entry.value.status.isActive) entry.key: entry.value,
    };
    for (final entry in _tasks.entries) {
      final local = merged[entry.key];
      if (local == null || !_preferLocalTask(local, entry.value)) {
        merged[entry.key] = entry.value;
      }
    }
    // Execution projections are transient progress-dialog mirrors; they are
    // deliberately excluded from the unified list so a finished producer can
    // never leave a stuck "进行中" row behind after the durable Go projection
    // no longer reports it.
    final result = merged.values.toList(growable: false)
      ..sort(sortRemoteTasksNewestFirst);
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
  // Total queue size (including retained history) last reported by Go. An
  // active-only poll returns no history rows, but must retain this full count.
  int get total => _hasServerTotal ? _total : _tasks.length;
  // True once the server sent a total explicitly; distinguishes a real 0
  // from an old binary that omitted the field.
  bool get hasServerTotal => _hasServerTotal;

  /// Public change notification for part-file helpers that mutate caches.
  void notifyListenersChanged() => notifyListeners();
  // Server-reported queue counts; zero-value means the backend has not
  // reported yet, and callers fall back to counting loaded rows.
  RemoteTaskQueueCounts get queue => _queue;
  bool get isRefreshing => _polling;
  bool get isLoadingInitialHistory => _loadingInitialHistory;

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
    _inFlightRead = null;
    _initialHistoryLoad = null;
    _loadingInitialHistory = false;
    _historyEpoch++;
    _tasks.clear();
    _nextCursor = '';
    _total = 0;
    _hasServerTotal = false;
    _queue = const RemoteTaskQueueCounts();
    _hasLoadedMore = false;
    _connectPushChannel();
    unawaited(pollActive());
    _ensurePolling();
  }

  // The bridge exposes a localhost websocket (make run sets CV_DEBUG_ADDR)
  // that ticks once per metadata op state change. Ticks trigger an immediate
  // poll; polling stays on as the correctness fallback if the socket dies.
  void _connectPushChannel() {
    _events?.dispose();
    _events = null;
    final debugAddr = const String.fromEnvironment(
      'CV_DEBUG_ADDR',
      defaultValue: '127.0.0.1:8765',
    );
    if (debugAddr.trim().isEmpty) return;
    _events = watchTaskEvents('ws://$debugAddr/debug/task-events', () {
      if (!_polling) unawaited(pollActive());
    });
  }

  Future<bool> cancel(String id) async {
    final local = _localTasks[id];
    final execution = _executionTasks[id];
    final remote = _tasks[id];
    if (local != null &&
        (remote == null || _preferLocalTask(local, remote)) &&
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
        (local != null &&
            (remote == null || _preferLocalTask(local, remote))) ||
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

  Future<void> loadMore({int? limit}) async {
    final api = _api;
    if (api == null) return;
    final generation = _bindingGeneration;
    final historyEpoch = _historyEpoch;
    // Join any read already in progress, then start the requested history page
    // under the same gate. This prevents page-entry loading from becoming a
    // no-op when another page has just called refresh().
    while (true) {
      final inFlightRead = _inFlightRead;
      if (inFlightRead != null) {
        await inFlightRead;
        if (_bindingGeneration != generation ||
            !identical(api, _api) ||
            _historyEpoch != historyEpoch) {
          return;
        }
        continue;
      }
      // An active-only poll leaves no cursor even when history exists, so the
      // first history request starts from page one explicitly.
      if (_nextCursor.isEmpty && _hasLoadedMore) return;
      final pageLimit = limit != null && limit > 0 ? limit : 100;
      await refresh(
        RemoteTaskFilter(
          cursor: _nextCursor,
          includeHistory: true,
          limit: pageLimit,
        ),
      );
      if (_bindingGeneration != generation ||
          !identical(api, _api) ||
          _historyEpoch != historyEpoch) {
        return;
      }
      // refresh reports transport failures through lastError. Do not consume
      // the one allowed first-history request until a page actually succeeds.
      if (_lastError == null) _hasLoadedMore = true;
      return;
    }
  }

  Future<bool> retry(String id) async {
    final local = _localTasks[id];
    final execution = _executionTasks[id];
    final remote = _tasks[id];
    if (local != null && (remote == null || _preferLocalTask(local, remote))) {
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
    if (local != null && (remote == null || _preferLocalTask(local, remote))) {
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
  }) => clearRemoteTaskHistory(
    this,
    profileId: profileId,
    bucket: bucket,
    taskIds: taskIds,
  );

  int _removeLocalTerminalTasks() =>
      removeTerminalTasks(tasks: _localTasks, onChanged: notifyListeners);

  int _removeLocalTerminalTasksById(Iterable<String> taskIds) =>
      removeTerminalTasksById(
        tasks: _localTasks,
        taskIds: taskIds,
        onChanged: notifyListeners,
      );

  int _removeExecutionTerminalTasks() =>
      removeTerminalTasks(tasks: _executionTasks, onChanged: notifyListeners);

  int _removeExecutionTasksById(Iterable<String> taskIds) =>
      removeTerminalTasksById(
        tasks: _executionTasks,
        taskIds: taskIds,
        onChanged: notifyListeners,
      );

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
    _events?.dispose();
    _events = null;
    _api = null;
    _polling = false;
    _inFlightRead = null;
    _initialHistoryLoad = null;
    _loadingInitialHistory = false;
    _lastError = null;
    _lastFreshAt = null;
    _freshness = '';
    _capabilities = const <String, bool>{};
    _nextCursor = '';
    _total = 0;
    _hasServerTotal = false;
    _queue = const RemoteTaskQueueCounts();
    _hasLoadedMore = false;
    _historyEpoch = 0;
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
