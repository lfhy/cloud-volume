// Remote task store polls the unified Go projection; legacy producers never
// become a display fallback when the remote-task endpoint is unavailable.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

class RemoteTaskStore extends ChangeNotifier {
  RemoteTaskStore._();

  static final RemoteTaskStore instance = RemoteTaskStore._();
  static const _activePollInterval = Duration(milliseconds: 700);
  static const _idlePollInterval = Duration(seconds: 2);

  final Map<String, RemoteTask> _tasks = <String, RemoteTask>{};
  RemoteStorageGateway? _api;
  Timer? _pollTimer;
  bool _polling = false;
  Duration? _pollInterval;
  Object? _lastError;
  DateTime? _lastFreshAt;
  String _freshness = '';
  Map<String, bool> _capabilities = const <String, bool>{};
  String _nextCursor = '';
  int _bindingGeneration = 0;

  List<RemoteTask> get tasks {
    final result = _tasks.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return result;
  }

  bool get hasActive => _tasks.values.any((task) => task.status.isActive);
  Object? get lastError => _lastError;
  DateTime? get lastFreshAt => _lastFreshAt;
  String get freshness => _freshness;
  Map<String, bool> get capabilities => _capabilities;
  String get nextCursor => _nextCursor;
  bool get isRefreshing => _polling;

  List<RemoteTask> tasksForProfile(String profileId) => tasks
      .where((task) => task.profileId == profileId)
      .toList(growable: false);

  void bindApi(RemoteStorageGateway api) {
    _bindingGeneration++;
    _api = api;
    unawaited(refresh());
    _ensurePolling();
  }

  Future<void> refresh([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async {
    if (_api == null || _polling) return;
    final generation = _bindingGeneration;
    _polling = true;
    try {
      final page = await _api!.listRemoteTasks(filter);
      if (filter.cursor.isEmpty) {
        _replaceRemoteTasks(page.items);
      } else {
        _replaceRemoteTasks(<RemoteTask>[...tasks, ...page.items]);
      }
      _nextCursor = page.nextCursor;
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
    final task = _tasks[id];
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
    if (_api == null) return _tasks[id];
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
    if (_api == null || _nextCursor.isEmpty || _polling) return;
    await refresh(RemoteTaskFilter(cursor: _nextCursor));
  }

  Future<bool> retry(String id) async {
    if (_api == null) return false;
    final result = await _api!.retryRemoteTask(id);
    await refresh();
    return result;
  }

  Future<bool> trigger(String id) async {
    if (_api == null) return false;
    final result = await _api!.triggerRemoteTask(id);
    await refresh();
    return result;
  }

  Future<int> clearHistory({String profileId = '', String bucket = ''}) async {
    if (_api == null) return 0;
    final removed = await _api!.clearRemoteTaskHistory(
      profileId: profileId,
      bucket: bucket,
    );
    await refresh();
    return removed;
  }

  void _replaceRemoteTasks(Iterable<RemoteTask> incoming) {
    final next = <String, RemoteTask>{
      for (final task in incoming) task.id: task,
    };
    if (mapEquals(_tasks, next)) return;
    _tasks
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void _ensurePolling() {
    if (_api == null) return;
    final interval = hasActive ? _activePollInterval : _idlePollInterval;
    if (_pollTimer != null && _pollInterval == interval) return;
    _pollTimer?.cancel();
    _pollInterval = interval;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(refresh()));
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
    _tasks.clear();
    notifyListeners();
  }
}
