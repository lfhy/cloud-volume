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
    Set<String> suppressObjectKeys = const <String>{},
    int? mobileNavigationEpoch,
    bool Function()? requestStillCurrent,
  }) async {
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
      epoch: mobileNavigationEpoch,
    );
    if (!_isCurrentMobileFileManagerRequest(request)) return false;
    _recordDesktopListingResumeTarget(
      _DesktopListingResumeTarget.objects(bucketEntry, prefix),
    );
    final listingViewGeneration = _beginListingViewRequest();
    bool isCurrentRequest() =>
        _isCurrentListingViewRequest(listingViewGeneration) &&
        _isCurrentMobileFileManagerRequest(request) &&
        (requestStillCurrent?.call() ?? true);
    if (!isCurrentRequest()) return false;
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
    // 显式刷新：先清掉当前页缓存再请求，避免请求失败时还显示旧的列表。
    if (forceRefresh) {
      _invalidateObjectListingCache(bucketId: bucketEntry.id, prefix: prefix);
      // 清掉内存里的列表，让加载态/错误态能在请求过程中正确显示。
      if (mounted && isCurrentRequest()) {
        setState(() {
          _objects = null;
          _objectsNextToken = '';
          _objectsHasMore = false;
          _pagingObjects = false;
        });
      }
    }
    try {
      final page = await _listObjectPageCached(
        bucketEntry,
        prefix,
        '',
        _FileManagerPageState._listPageSize,
        forceRefresh: forceRefresh,
        mobileRequest: request,
        requestStillCurrent: isCurrentRequest,
        listingViewGeneration: listingViewGeneration,
      );
      final pageItems = suppressObjectKeys.isEmpty
          ? page.items
          : page.items
                .where((object) => !suppressObjectKeys.contains(object.key))
                .toList(growable: false);
      if (suppressObjectKeys.isNotEmpty && isCurrentRequest()) {
        // A successful delete is authoritative even if the provider briefly
        // returns a stale row. Drop the raw page cache so later navigation
        // rechecks the backend instead of resurrecting that stale snapshot.
        _invalidateObjectListingCache(bucketId: bucketEntry.id, prefix: prefix);
      }
      if (!mounted || !isCurrentRequest()) {
        return false;
      }
      setState(() {
        final visibleKeys = pageItems.map((object) => object.key).toSet();
        _activeBucketEntry = bucketEntry;
        _objects = pageItems;
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
      if (!mounted || !isCurrentRequest()) {
        return false;
      }
      setState(() {
        _error = describeBridgeError(e);
        _endLoading();
      });
      return false;
    }
  }

  Future<void> _navToBucket(FileManagerBucketEntry bucketEntry) {
    if (_isTrashHome) {
      return _openBucketTrash(bucket: bucketEntry);
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
    _MobileFileManagerRequest? mobileRequest,
    bool Function()? requestStillCurrent,
    int? listingViewGeneration,
  }) async {
    final key = _ObjectListingCacheKey(
      bucketId: bucketEntry.id,
      prefix: prefix,
      nextToken: nextToken,
      pageSize: pageSize,
    );
    if (forceRefresh) {
      // 显式刷新/写后重载：必须把整页缓存清掉，否则切换页 token 时还会命中旧条目。
      _invalidateObjectListingCache(bucketId: bucketEntry.id, prefix: prefix);
    } else {
      final cached = _objectListingCache[key];
      if (cached != null) {
        return cached;
      }
    }
    // An invalidation may happen while this request is on the wire. Keep a
    // separate cache epoch so that response cannot repopulate an invalidated
    // page even when its visible-view request is no longer active.
    final cacheGeneration = _objectListingCacheGeneration;
    final page = await widget.api.listObjectPage(
      bucketEntry.config,
      bucketEntry.bucket.name,
      prefix,
      nextToken,
      pageSize,
      forceRefresh: forceRefresh,
    );
    // 即便是 forceRefresh，也只在请求成功后才写入缓存；失败时不污染缓存，
    // 这样用户重试时仍会真正请求后端而不是返回上一次的错误快照。
    // A response that lost its Android location/epoch or sync-ticket race may
    // still finish after the UI dropped it. Never cache stale pages.
    if (_isCurrentMobileFileManagerRequest(mobileRequest) &&
        (requestStillCurrent?.call() ?? true) &&
        (listingViewGeneration == null ||
            _isCurrentListingViewRequest(listingViewGeneration)) &&
        cacheGeneration == _objectListingCacheGeneration) {
      _objectListingCache[key] = page;
    }
    return page;
  }

  FileAccessDirectoryLister? _downloadDirectoryLister({
    FileManagerBucketEntry? bucketEntry,
    _MobileFileManagerRequest? mobileRequest,
    int? listingViewGeneration,
    bool Function()? requestStillCurrent,
  }) {
    bucketEntry ??= _activeBucketEntry;
    if (bucketEntry == null) {
      return null;
    }
    return (prefix) => _listObjectsForDownload(
      bucketEntry!,
      prefix,
      mobileRequest: mobileRequest,
      listingViewGeneration: listingViewGeneration,
      requestStillCurrent: requestStillCurrent,
    );
  }

  Future<List<ObjectInfo>> _listObjectsForDownload(
    FileManagerBucketEntry bucketEntry,
    String prefix, {
    _MobileFileManagerRequest? mobileRequest,
    int? listingViewGeneration,
    bool Function()? requestStillCurrent,
  }) async {
    final items = <ObjectInfo>[];
    var nextToken = '';
    do {
      if (!(requestStillCurrent?.call() ?? true)) {
        throw StateError('下载源已更新，请在当前目录重新开始下载。');
      }
      final page = await _listObjectPageCached(
        bucketEntry,
        prefix,
        nextToken,
        _FileManagerPageState._listPageSize,
        mobileRequest: mobileRequest,
        listingViewGeneration: listingViewGeneration,
        requestStillCurrent: requestStillCurrent,
      );
      if (!(requestStillCurrent?.call() ?? true)) {
        throw StateError('下载源已更新，请在当前目录重新开始下载。');
      }
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
    // In-flight page requests retain this epoch and cannot reinsert an old
    // page after a write (including a timeout with an unknown remote result).
    _objectListingCacheGeneration++;
    _objectListingCache.removeWhere((key, _) {
      final bucketMatches = bucketId == null || key.bucketId == bucketId;
      final prefixMatches = prefix == null || key.prefix == prefix;
      return bucketMatches && prefixMatches;
    });
  }

  Future<bool> _reloadObjectsAfterBucketMutation(
    FileManagerBucketEntry bucketEntry,
    String prefix, {
    Set<String> suppressObjectKeys = const <String>{},
    int? mobileNavigationEpoch,
  }) {
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
      epoch: mobileNavigationEpoch,
    );
    if (!_isCurrentMobileFileManagerRequest(request)) {
      return Future<bool>.value(false);
    }
    final reloadRequest = _supersedeMobileFileManagerRequest(request);
    _invalidateObjectListingCache(bucketId: bucketEntry.id);
    return _loadObjects(
      bucketEntry,
      prefix,
      forceRefresh: true,
      suppressObjectKeys: suppressObjectKeys,
      mobileNavigationEpoch: reloadRequest?.epoch,
    );
  }

  Future<void> _recoverObjectsAfterUncertainMutation(
    FileManagerBucketEntry bucketEntry,
    String prefix,
    int sourceListingViewGeneration,
  ) async {
    // A transport failure can arrive after the provider committed the write.
    // Always expire its cache, then refresh only if this source is still open.
    _invalidateObjectListingCache(bucketId: bucketEntry.id);
    if (!_isCurrentObjectMutationSource(
      bucketEntry,
      prefix,
      sourceListingViewGeneration,
    )) {
      return;
    }
    await _reloadObjectsAfterBucketMutation(bucketEntry, prefix);
  }

  bool _isCurrentObjectMutationSource(
    FileManagerBucketEntry bucketEntry,
    String prefix,
    int sourceListingViewGeneration,
  ) {
    if (!mounted) return false;
    if (_usesMobileNavigation) {
      // Rebinding retains bucket IDs for Back history but replaces their config
      // entries. A mutation captured before that replacement may only expire
      // cache; it must never reload through its old endpoint/root prefix.
      return !_mobileInputRefreshNeedsRebind &&
          _mobileInputGenerationByListingView[sourceListingViewGeneration] ==
              _mobileInputGeneration &&
          identical(_mobileLocation.bucket, bucketEntry) &&
          identical(_activeBucketEntry, bucketEntry) &&
          _mobileLocation.matches(
            _MobileFileManagerLocation.objects(bucketEntry, prefix),
          );
    }
    // A sync target has not yet committed its new desktop resume target
    // during discovery. Its generation fence keeps old A mutations from
    // canceling that pending B open, while normal A→B→A follows identity.
    if (_activeDesktopSyncRemoteOpenGeneration != null &&
        !_isCurrentListingViewRequest(sourceListingViewGeneration)) {
      return false;
    }
    return _desktopListingResumeTarget?.matches(
          _DesktopListingResumeTarget.objects(bucketEntry, prefix),
        ) ??
        false;
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
      unawaited(
        _refreshDirectoryAccess(bucketEntry, prefix, _listingViewGeneration),
      );
    }
  }
}
