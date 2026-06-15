// 文件管理页目录加载：集中处理对象列表内存缓存、导航和显式刷新语义。
// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

class _ObjectListingCacheKey {
  const _ObjectListingCacheKey({
    required this.bucketId,
    required this.prefix,
    required this.nextToken,
    required this.pageSize,
  });

  final String bucketId;
  final String prefix;
  final String nextToken;
  final int pageSize;

  @override
  bool operator ==(Object other) {
    return other is _ObjectListingCacheKey &&
        other.bucketId == bucketId &&
        other.prefix == prefix &&
        other.nextToken == nextToken &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(bucketId, prefix, nextToken, pageSize);
}

extension _FileManagerPageObjectLoading on _FileManagerPageState {
  Future<bool> _loadObjects(
    FileManagerBucketEntry bucketEntry,
    String prefix, {
    bool forceRefresh = false,
  }) async {
    final mayWaitForBaiduRetry =
        bucketEntry.config.storageType == StorageType.baiduPan &&
        (forceRefresh ||
            !_hasObjectListingCache(
              bucketEntry,
              prefix,
              '',
              _FileManagerPageState._listPageSize,
            ));
    _beginLoading(
      delayedDetail: mayWaitForBaiduRetry ? '百度网盘可能触发频率限制，正在等待自动重试...' : null,
    );
    try {
      final page = await _listObjectPageCached(
        bucketEntry,
        prefix,
        '',
        _FileManagerPageState._listPageSize,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return false;
      setState(() {
        final visibleKeys = page.items.map((object) => object.key).toSet();
        _activeBucketEntry = bucketEntry;
        _objects = page.items;
        _trashItems = null;
        _prefix = prefix;
        _breadcrumbs = prefix.split('/').where((s) => s.isNotEmpty).toList();
        _showTrash = false;
        _objectsNextToken = page.nextToken;
        _objectsHasMore = page.hasMore;
        _pagingObjects = false;
        _directoryAccess = null;
        _checkingDirectoryAccess =
            bucketEntry.config.storageType == StorageType.webdav;
        _trashNextToken = '';
        _trashHasMore = false;
        _pagingTrash = false;
        _selectedObjectKeys.clear();
        _deletingObjectKeys.removeWhere((key) => !visibleKeys.contains(key));
        _endLoading();
      });
      _afterObjectListingLoaded(bucketEntry, prefix);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _error = describeBridgeError(e);
        _endLoading();
      });
      return false;
    }
  }

  Future<void> _navToBucket(FileManagerBucketEntry bucketEntry) {
    if (_isTrashHome) {
      return _openBucketTrash(bucketEntry);
    }
    return _loadObjects(bucketEntry, '');
  }

  Future<void> _navToPrefix(String prefix) {
    if (_activeBucketEntry == null) return Future.value();
    return _loadObjects(_activeBucketEntry!, prefix);
  }

  Future<void> _navUp() {
    if (_activeBucketEntry == null) return Future.value();
    final parts = _prefix.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return _loadBuckets();
    parts.removeLast();
    return _loadObjects(
      _activeBucketEntry!,
      parts.map((part) => '$part/').join(),
    );
  }

  Future<void> _navCrumb(int index) {
    if (_activeBucketEntry == null) return Future.value();
    if (index < 0) return _loadBuckets();
    return _loadObjects(
      _activeBucketEntry!,
      _breadcrumbs.sublist(0, index + 1).map((segment) => '$segment/').join(),
    );
  }

  Future<ObjectListPage> _listObjectPageCached(
    FileManagerBucketEntry bucketEntry,
    String prefix,
    String nextToken,
    int pageSize, {
    bool forceRefresh = false,
  }) async {
    final key = _ObjectListingCacheKey(
      bucketId: bucketEntry.id,
      prefix: prefix,
      nextToken: nextToken,
      pageSize: pageSize,
    );
    if (forceRefresh) {
      _invalidateObjectListingCache(bucketId: bucketEntry.id, prefix: prefix);
    } else {
      final cached = _objectListingCache[key];
      if (cached != null) {
        return cached;
      }
    }
    final page = await widget.api.listObjectPage(
      bucketEntry.config,
      bucketEntry.bucket.name,
      prefix,
      nextToken,
      pageSize,
    );
    _objectListingCache[key] = page;
    return page;
  }

  FileAccessDirectoryLister? _downloadDirectoryLister() {
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) {
      return null;
    }
    return (prefix) => _listObjectsForDownload(bucketEntry, prefix);
  }

  Future<List<ObjectInfo>> _listObjectsForDownload(
    FileManagerBucketEntry bucketEntry,
    String prefix,
  ) async {
    final items = <ObjectInfo>[];
    var nextToken = '';
    do {
      final page = await _listObjectPageCached(
        bucketEntry,
        prefix,
        nextToken,
        _FileManagerPageState._listPageSize,
      );
      items.addAll(page.items);
      nextToken = page.nextToken;
    } while (nextToken.isNotEmpty);
    return items;
  }

  bool _hasObjectListingCache(
    FileManagerBucketEntry bucketEntry,
    String prefix,
    String nextToken,
    int pageSize,
  ) {
    return _objectListingCache.containsKey(
      _ObjectListingCacheKey(
        bucketId: bucketEntry.id,
        prefix: prefix,
        nextToken: nextToken,
        pageSize: pageSize,
      ),
    );
  }

  void _invalidateObjectListingCache({String? bucketId, String? prefix}) {
    _objectListingCache.removeWhere((key, _) {
      final bucketMatches = bucketId == null || key.bucketId == bucketId;
      final prefixMatches = prefix == null || key.prefix == prefix;
      return bucketMatches && prefixMatches;
    });
  }

  Future<bool> _reloadObjectsAfterBucketMutation(
    FileManagerBucketEntry bucketEntry,
    String prefix,
  ) {
    _invalidateObjectListingCache(bucketId: bucketEntry.id);
    return _loadObjects(bucketEntry, prefix, forceRefresh: true);
  }

  void _afterObjectListingLoaded(
    FileManagerBucketEntry bucketEntry,
    String prefix,
  ) {
    if (_contentScrollController.hasClients) {
      _contentScrollController.jumpTo(0);
    }
    if (bucketEntry.config.supportsMounts &&
        widget.api.capabilities.supportsMounts) {
      unawaited(_refreshMountStatus(bucketEntry));
    }
    if (bucketEntry.config.storageType == StorageType.webdav) {
      unawaited(_refreshDirectoryAccess(bucketEntry, prefix));
    }
  }
}
