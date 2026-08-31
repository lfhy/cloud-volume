// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件列表恢复同步：监听回收站恢复事件，并静默刷新当前命中的对象列表缓存。

class _PendingUploadRefresh {
  const _PendingUploadRefresh({
    required this.bucketId,
    required this.prefix,
    required this.sourceListingViewGeneration,
  });

  final String bucketId;
  final String prefix;
  final int sourceListingViewGeneration;
}

class _PendingMetadataTaskRefresh {
  _PendingMetadataTaskRefresh({
    required this.bucketId,
    required this.bucket,
    required this.profileId,
    required this.prefix,
    required this.path,
    required this.startedAt,
    required this.sourceListingViewGeneration,
  });

  final String bucketId;
  final String bucket;
  final String profileId;
  final String prefix;
  final String path;
  final DateTime startedAt;
  final int sourceListingViewGeneration;
  // RemoteTaskStore intentionally evicts terminal rows in active-only mode.
  // Only an observed active state lets a later absence mean completion.
  bool sawActive = false;
}

extension _FileManagerPageRestoreSync on _FileManagerPageState {
  void _handleObjectListingMutation() {
    final event = ObjectListingNotifier.instance.latestEvent;
    if (event == null || event.version <= _seenObjectListingMutationVersion) {
      return;
    }
    _seenObjectListingMutationVersion = event.version;
    if (event.kind != ObjectListingMutationKind.restored) {
      return;
    }
    _invalidateObjectListingCacheForRestoredBucket(event.bucket);
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null ||
        _activeBucket != event.bucket ||
        _showTrash ||
        _loading ||
        _error != null ||
        !_isCurrentObjectMutationSource(
          bucketEntry,
          _prefix,
          _listingViewGeneration,
        ) ||
        !_restoredEntriesAffectCurrentListing(event.entries)) {
      return;
    }
    unawaited(_refreshActiveObjectListingAfterRestore());
  }

  void _invalidateObjectListingCacheForRestoredBucket(String bucket) {
    final matchingIds = _buckets
        ?.where((entry) => entry.bucket.name == bucket)
        .map((entry) => entry.id)
        .toList(growable: false);
    if (matchingIds == null || matchingIds.isEmpty) {
      _invalidateObjectListingCache();
      return;
    }
    for (final id in matchingIds) {
      _invalidateObjectListingCache(bucketId: id);
    }
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

  Future<void> _refreshActiveObjectListingAfterRestore({
    String? expectedBucketId,
    String? expectedPrefix,
    int? sourceListingViewGeneration,
  }) async {
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null || _showTrash) {
      return;
    }
    if (sourceListingViewGeneration != null &&
        (bucketEntry.id != expectedBucketId ||
            _prefix != expectedPrefix ||
            !_isCurrentObjectMutationSource(
              bucketEntry,
              _prefix,
              sourceListingViewGeneration,
            ))) {
      return;
    }
    final bucket = bucketEntry.bucket.name;
    final prefix = _prefix;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
    );
    if (!_isCurrentMobileFileManagerRequest(request)) return;
    final listingViewGeneration = _beginListingViewRequest();
    final refreshRequest = _supersedeMobileFileManagerRequest(request);
    try {
      final page = await _listObjectPageCached(
        bucketEntry,
        prefix,
        '',
        _FileManagerPageState._listPageSize,
        forceRefresh: true,
        mobileRequest: refreshRequest,
        requestStillCurrent: () =>
            _isCurrentListingViewRequest(listingViewGeneration),
        listingViewGeneration: listingViewGeneration,
      );
      if (!mounted ||
          !_isCurrentMobileFileManagerRequest(refreshRequest) ||
          !_isCurrentListingViewRequest(listingViewGeneration) ||
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
        _selectedObjectKeys.removeWhere((key) => !visibleKeys.contains(key));
        _deletingObjectKeys.removeWhere((key) => !visibleKeys.contains(key));
      });
    } catch (_) {
      // 静默刷新失败不打断当前页，用户仍可手动刷新重试。
    } finally {
      // This refresh supersedes an older page-two request. Its finally block
      // is intentionally stale, so the current refresh owns releasing the
      // pagination guard even when its own request fails.
      if (mounted &&
          _isCurrentMobileFileManagerRequest(refreshRequest) &&
          _isCurrentListingViewRequest(listingViewGeneration) &&
          _activeBucket == bucket &&
          _prefix == prefix &&
          !_showTrash) {
        setState(() => _pagingObjects = false);
      }
    }
  }

  void _trackUploadTaskForRefresh(
    String taskId,
    String bucketId,
    String prefix,
    int sourceListingViewGeneration,
  ) {
    _invalidateObjectListingCache(bucketId: bucketId);
    _pendingUploadRefreshes[taskId] = _PendingUploadRefresh(
      bucketId: bucketId,
      prefix: prefix,
      sourceListingViewGeneration: sourceListingViewGeneration,
    );
    // A very fast directory upload can publish its terminal queue state before
    // this tracker is registered, so inspect the local status immediately.
    _handleUploadTaskRefresh();
  }

  void _trackMetadataTaskForRefresh({
    required String bucketId,
    required String bucket,
    required String profileId,
    required String prefix,
    required String path,
    required DateTime startedAt,
    required int sourceListingViewGeneration,
  }) {
    final key = '$bucketId:$path:${startedAt.microsecondsSinceEpoch}';
    _pendingMetadataTaskRefreshes[key] = _PendingMetadataTaskRefresh(
      bucketId: bucketId,
      bucket: bucket,
      profileId: profileId,
      prefix: prefix,
      path: path,
      startedAt: startedAt,
      sourceListingViewGeneration: sourceListingViewGeneration,
    );
    _handleUploadTaskRefresh();
    unawaited(RemoteTaskStore.instance.refresh());
  }

  void _handleUploadTaskRefresh() {
    final tasks = RemoteTaskStore.instance.tasks;
    _refreshTrackedMetadataTasks(tasks);
    _refreshOnMetadataTaskCompletion(tasks);
    if (_pendingUploadRefreshes.isEmpty) return;
    final finishedIds = <String>[];
    for (final entry in _pendingUploadRefreshes.entries) {
      final id = entry.key.startsWith('transfer:')
          ? entry.key
          : 'transfer:${entry.key}';
      final task = tasks.where((candidate) => candidate.id == id).firstOrNull;
      final localStatus = TransferQueue.instance.statusOf(entry.key);
      final localTerminal =
          localStatus == TransferStatus.done ||
          localStatus == TransferStatus.failed ||
          localStatus == TransferStatus.canceled;
      final remoteTerminal = task != null && !task.status.isActive;
      if (!localTerminal && !remoteTerminal) {
        continue;
      }
      finishedIds.add(entry.key);
      // A directory task may complete after its source view was hidden and
      // its old page cache refilled. Terminal state is another mutation
      // boundary even when no source-view refresh is currently allowed.
      _invalidateObjectListingCache(bucketId: entry.value.bucketId);
      if (!_showTrash &&
          !_loading &&
          _activeBucketId == entry.value.bucketId &&
          _prefix == entry.value.prefix) {
        unawaited(_refreshActiveObjectListingAfterUpload(entry.value));
      }
    }
    for (final id in finishedIds) {
      _pendingUploadRefreshes.remove(id);
    }
  }

  void _refreshTrackedMetadataTasks(List<RemoteTask> tasks) {
    if (_pendingMetadataTaskRefreshes.isEmpty) {
      return;
    }
    final completed = <String>[];
    for (final entry in _pendingMetadataTaskRefreshes.entries) {
      final task = tasks
          .where((candidate) => _matchesMetadataRefresh(candidate, entry.value))
          .firstOrNull;
      if (task?.status.isActive == true) {
        entry.value.sawActive = true;
        continue;
      }
      // Active-only snapshots remove a terminal metadata task. Do not treat a
      // never-observed task as done: bridge publication can lag task admission.
      if (task == null && !entry.value.sawActive) continue;
      completed.add(entry.key);
      _invalidateObjectListingCache(bucketId: entry.value.bucketId);
      if (!_showTrash &&
          !_loading &&
          _activeBucketId == entry.value.bucketId &&
          _prefix == entry.value.prefix) {
        _scheduleMetadataTaskListingRefresh(
          expectedBucketId: entry.value.bucketId,
          expectedPrefix: entry.value.prefix,
          sourceListingViewGeneration: entry.value.sourceListingViewGeneration,
        );
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
    if (_loading || _error != null) {
      return;
    }
    final sourceBucketId = _activeBucketId;
    final sourcePrefix = _prefix;
    final sourceListingViewGeneration = _listingViewGeneration;
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
    if (refresh && sourceBucketId != null) {
      _scheduleMetadataTaskListingRefresh(
        expectedBucketId: sourceBucketId,
        expectedPrefix: sourcePrefix,
        sourceListingViewGeneration: sourceListingViewGeneration,
      );
    }
  }

  bool _metadataTaskAffectsCurrentListing(RemoteTask task) {
    final bucketEntry = _activeBucketEntry;
    final bucket = _activeBucket;
    final profileId = _activeConfig.profileId.trim();
    if (bucketEntry == null ||
        bucket == null ||
        _showTrash ||
        !_isCurrentObjectMutationSource(
          bucketEntry,
          _prefix,
          _listingViewGeneration,
        ) ||
        task.bucket.trim() != bucket) {
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

  void _scheduleMetadataTaskListingRefresh({
    String? expectedBucketId,
    String? expectedPrefix,
    int? sourceListingViewGeneration,
  }) {
    if (_metadataTaskRefreshInFlight) return;
    _metadataTaskRefreshInFlight = true;
    unawaited(
      _refreshActiveObjectListingAfterRestore(
        expectedBucketId: expectedBucketId,
        expectedPrefix: expectedPrefix,
        sourceListingViewGeneration: sourceListingViewGeneration,
      ).whenComplete(() => _metadataTaskRefreshInFlight = false),
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
        !_isCurrentObjectMutationSource(
          bucket,
          refresh.prefix,
          refresh.sourceListingViewGeneration,
        )) {
      return;
    }
    await _refreshActiveObjectListingAfterRestore(
      expectedBucketId: refresh.bucketId,
      expectedPrefix: refresh.prefix,
      sourceListingViewGeneration: refresh.sourceListingViewGeneration,
    );
  }
}
