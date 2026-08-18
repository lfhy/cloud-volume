// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件列表恢复同步：监听回收站恢复事件，并静默刷新当前命中的对象列表缓存。

class _PendingUploadRefresh {
  const _PendingUploadRefresh({required this.bucketId, required this.prefix});

  final String bucketId;
  final String prefix;
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

  void _handleUploadTaskRefresh() {
    if (_pendingUploadRefreshes.isEmpty || _showTrash || _loading) {
      return;
    }
    final tasks = RemoteTaskStore.instance.tasks;
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
