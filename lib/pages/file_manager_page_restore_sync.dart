// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件列表恢复同步：监听回收站恢复事件，并静默刷新当前命中的对象列表缓存。

class _PendingUploadRefresh {
  const _PendingUploadRefresh({required this.bucketId, required this.prefix});

  final String bucketId;
  final String prefix;
}

class _PendingMetadataTaskRefresh {
  const _PendingMetadataTaskRefresh({
    required this.bucketId,
    required this.bucket,
    required this.profileId,
    required this.prefix,
    required this.path,
    required this.startedAt,
  });

  final String bucketId;
  final String bucket;
  final String profileId;
  final String prefix;
  final String path;
  final DateTime startedAt;
}

extension _FileManagerPageRestoreSync on _FileManagerPageState {
  void _handleObjectListingMutation() {
    final event = ObjectListingNotifier.instance.latestEvent;
    if (event == null || event.version <= _seenObjectListingMutationVersion) {
      return;
    }
    _seenObjectListingMutationVersion = event.version;
    if (event.kind != ObjectListingMutationKind.restored ||
        _activeBucket != event.bucket ||
        _showTrash ||
        _loading ||
        !_restoredEntriesAffectCurrentListing(event.entries)) {
      return;
    }
    unawaited(_refreshActiveObjectListingAfterRestore());
  }

  bool _restoredEntriesAffectCurrentListing(List<RestoredObjectEntry> entries) {
    if (_prefix.isEmpty) {
      return entries.isNotEmpty;
    }
    return entries.any(
      (entry) =>
          entry.objectKey == _prefix || entry.objectKey.startsWith(_prefix),
    );
  }

  Future<void> _refreshActiveObjectListingAfterRestore() async {
    final bucket = _activeBucket;
    if (bucket == null || _showTrash) {
      return;
    }
    final prefix = _prefix;
    try {
      final page = await _listObjectPageCached(
        _activeBucketEntry!,
        prefix,
        '',
        _FileManagerPageState._listPageSize,
        forceRefresh: true,
      );
      if (!mounted ||
          _activeBucket != bucket ||
          _prefix != prefix ||
          _showTrash) {
        return;
      }
      setState(() {
        final visibleKeys = page.items.map((object) => object.key).toSet();
        _objects = page.items;
        _objectsNextToken = page.nextToken;
        _objectsHasMore = page.hasMore;
        _pagingObjects = false;
        _selectedObjectKeys.removeWhere((key) => !visibleKeys.contains(key));
        _deletingObjectKeys.removeWhere((key) => !visibleKeys.contains(key));
      });
    } catch (_) {
      // 静默刷新失败不打断当前页，用户仍可手动刷新重试。
    }
  }

  void _trackUploadTaskForRefresh(
    String taskId,
    String bucketId,
    String prefix,
  ) {
    _invalidateObjectListingCache(bucketId: bucketId);
    _pendingUploadRefreshes[taskId] = _PendingUploadRefresh(
      bucketId: bucketId,
      prefix: prefix,
    );
  }

  void _trackMetadataTaskForRefresh({
    required String bucketId,
    required String bucket,
    required String profileId,
    required String prefix,
    required String path,
    required DateTime startedAt,
  }) {
    final key = '$bucketId:$path:${startedAt.microsecondsSinceEpoch}';
    _pendingMetadataTaskRefreshes[key] = _PendingMetadataTaskRefresh(
      bucketId: bucketId,
      bucket: bucket,
      profileId: profileId,
      prefix: prefix,
      path: path,
      startedAt: startedAt,
    );
    unawaited(RemoteTaskStore.instance.refresh());
  }

  void _handleUploadTaskRefresh() {
    final tasks = RemoteTaskStore.instance.tasks;
    _refreshTrackedMetadataTasks(tasks);
    _refreshOnMetadataTaskCompletion(tasks);
    if (_pendingUploadRefreshes.isEmpty || _showTrash || _loading) return;
    final finishedIds = <String>[];
    for (final entry in _pendingUploadRefreshes.entries) {
      final id = entry.key.startsWith('transfer:')
          ? entry.key
          : 'transfer:${entry.key}';
      final task = tasks.where((candidate) => candidate.id == id).firstOrNull;
      if (task == null || task.status.isActive) {
        continue;
      }
      finishedIds.add(entry.key);
      if (_activeBucketId == entry.value.bucketId &&
          _prefix == entry.value.prefix) {
        unawaited(_refreshActiveObjectListingAfterUpload(entry.value));
      }
    }
    for (final id in finishedIds) {
      _pendingUploadRefreshes.remove(id);
    }
  }

  void _refreshTrackedMetadataTasks(List<RemoteTask> tasks) {
    if (_pendingMetadataTaskRefreshes.isEmpty || _showTrash || _loading) {
      return;
    }
    final completed = <String>[];
    for (final entry in _pendingMetadataTaskRefreshes.entries) {
      final task = tasks
          .where((candidate) => _matchesMetadataRefresh(candidate, entry.value))
          .firstOrNull;
      if (task == null || task.status.isActive) continue;
      completed.add(entry.key);
      if (_activeBucketId == entry.value.bucketId &&
          _prefix == entry.value.prefix) {
        _scheduleMetadataTaskListingRefresh();
      }
    }
    for (final key in completed) {
      _pendingMetadataTaskRefreshes.remove(key);
    }
  }

  bool _matchesMetadataRefresh(
    RemoteTask task,
    _PendingMetadataTaskRefresh refresh,
  ) {
    if (task.source != RemoteTaskSource.metadata ||
        task.bucket.trim() != refresh.bucket ||
        task.profileId.trim() != refresh.profileId) {
      return false;
    }
    final createdAt = DateTime.tryParse(task.createdAt);
    if (createdAt == null ||
        createdAt.isBefore(
          refresh.startedAt.subtract(const Duration(seconds: 5)),
        )) {
      return false;
    }
    final target = _normalizedMetadataPath(refresh.path);
    return _metadataTaskPaths(
      task,
    ).any((path) => _normalizedMetadataPath(path) == target);
  }

  void _refreshOnMetadataTaskCompletion(List<RemoteTask> tasks) {
    var refresh = false;
    final visible = <String>{};
    for (final task in tasks) {
      if (task.source != RemoteTaskSource.metadata) continue;
      visible.add(task.id);
      final previous = _seenMetadataTaskStates[task.id];
      _seenMetadataTaskStates[task.id] = task.status;
      if (previous?.isActive == true &&
          !task.status.isActive &&
          _metadataTaskAffectsCurrentListing(task)) {
        refresh = true;
      }
    }
    _seenMetadataTaskStates.removeWhere((id, _) => !visible.contains(id));
    if (refresh) _scheduleMetadataTaskListingRefresh();
  }

  bool _metadataTaskAffectsCurrentListing(RemoteTask task) {
    final bucket = _activeBucket;
    final profileId = _activeConfig.profileId.trim();
    if (bucket == null || _showTrash || task.bucket.trim() != bucket) {
      return false;
    }
    if (profileId.isNotEmpty && task.profileId.trim() != profileId) {
      return false;
    }
    final prefix = _normalizedMetadataPath(_prefix);
    return _metadataTaskPaths(task).any((path) {
      final taskPath = _normalizedMetadataPath(path);
      return taskPath.isNotEmpty &&
          (prefix.isEmpty ||
              taskPath == prefix ||
              taskPath.startsWith('$prefix/'));
    });
  }

  Iterable<String> _metadataTaskPaths(RemoteTask task) sync* {
    yield task.sourcePath;
    yield task.targetPath;
    yield task.displayPath;
    for (final event in task.events) {
      yield event.sourcePath;
      yield event.targetPath;
    }
  }

  void _scheduleMetadataTaskListingRefresh() {
    if (_metadataTaskRefreshInFlight) return;
    _metadataTaskRefreshInFlight = true;
    unawaited(
      _refreshActiveObjectListingAfterRestore().whenComplete(
        () => _metadataTaskRefreshInFlight = false,
      ),
    );
  }

  String _normalizedMetadataPath(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^/+'), '')
      .replaceFirst(RegExp(r'/+$'), '');

  Future<void> _refreshActiveObjectListingAfterUpload(
    _PendingUploadRefresh refresh,
  ) async {
    final bucket = _activeBucketEntry;
    if (bucket == null ||
        bucket.id != refresh.bucketId ||
        _prefix != refresh.prefix ||
        _showTrash) {
      return;
    }
    await _refreshActiveObjectListingAfterRestore();
  }
}
