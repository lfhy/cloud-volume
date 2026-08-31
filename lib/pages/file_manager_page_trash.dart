// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页回收站逻辑：按 bucket 浏览、恢复和彻底删除软删除对象。

extension _FileManagerPageTrash on _FileManagerPageState {
  Future<bool> _openBucketTrash({
    FileManagerBucketEntry? bucket,
    int? mobileNavigationEpoch,
  }) async {
    final targetBucket = bucket ?? _activeBucketEntry;
    if (targetBucket == null) {
      return false;
    }
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.trash(targetBucket),
      epoch: mobileNavigationEpoch,
    );
    if (!_isCurrentMobileFileManagerRequest(request)) {
      return false;
    }
    _recordDesktopListingResumeTarget(
      _DesktopListingResumeTarget.trash(targetBucket),
    );
    final listingViewGeneration = _beginListingViewRequest();
    _beginLoading(message: '加载回收站...');
    try {
      final page = await widget.api.listTrashPage(
        targetBucket.config,
        targetBucket.bucket.name,
        '',
        _FileManagerPageState._trashPageSize,
      );
      if (!mounted ||
          !_isCurrentListingViewRequest(listingViewGeneration) ||
          !_isCurrentMobileFileManagerRequest(request)) {
        return false;
      }
      setState(() {
        _activeBucketEntry = targetBucket;
        _objects = null;
        _trashItems = page.items;
        _prefix = '';
        _breadcrumbs = const <String>[];
        _showTrash = true;
        _objectsNextToken = '';
        _objectsHasMore = false;
        _pagingObjects = false;
        _trashNextToken = page.nextToken;
        _trashHasMore = page.hasMore;
        _pagingTrash = false;
        _selectedObjectKeys.clear();
        _endLoading();
      });
      if (_contentScrollController.hasClients) {
        _contentScrollController.jumpTo(0);
      }
      return true;
    } catch (error) {
      if (!mounted ||
          !_isCurrentListingViewRequest(listingViewGeneration) ||
          !_isCurrentMobileFileManagerRequest(request)) {
        return false;
      }
      setState(() {
        _error = error.toString();
        _endLoading();
      });
      return false;
    }
  }

  Future<void> _closeBucketTrash() async {
    if (_isTrashHome) {
      await _loadBuckets();
      return;
    }
    if (_activeBucket == null) {
      return;
    }
    await _loadObjects(_activeBucketEntry!, '');
  }

  Future<bool> _reloadBucketTrashAfterMutation(
    FileManagerBucketEntry bucketEntry, {
    int? mobileNavigationEpoch,
  }) {
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.trash(bucketEntry),
      epoch: mobileNavigationEpoch,
    );
    if (!_isCurrentMobileFileManagerRequest(request)) {
      return Future<bool>.value(false);
    }
    final reloadRequest = _supersedeMobileFileManagerRequest(request);
    return _openBucketTrash(
      bucket: bucketEntry,
      mobileNavigationEpoch: reloadRequest?.epoch,
    );
  }

  bool _isCurrentTrashMutationSource(
    FileManagerBucketEntry bucketEntry,
    int sourceListingViewGeneration,
  ) {
    if (!mounted) return false;
    if (widget.viewBuilder != null) {
      // The logical trash location may keep its ID after a profile refresh,
      // but only the rebound entry is allowed to reload it.
      return !_mobileInputRefreshNeedsRebind &&
          _mobileInputGenerationByListingView[sourceListingViewGeneration] ==
              _mobileInputGeneration &&
          identical(_mobileLocation.bucket, bucketEntry) &&
          identical(_activeBucketEntry, bucketEntry) &&
          _mobileLocation.matches(
            _MobileFileManagerLocation.trash(bucketEntry),
          );
    }
    if (_activeDesktopSyncRemoteOpenGeneration != null &&
        !_isCurrentListingViewRequest(sourceListingViewGeneration)) {
      return false;
    }
    return _desktopListingResumeTarget?.matches(
          _DesktopListingResumeTarget.trash(bucketEntry),
        ) ??
        false;
  }

  Future<void> _recoverTrashAfterUncertainMutation(
    FileManagerBucketEntry bucketEntry,
    int sourceListingViewGeneration,
  ) async {
    if (!_isCurrentTrashMutationSource(
      bucketEntry,
      sourceListingViewGeneration,
    )) {
      return;
    }
    await _reloadBucketTrashAfterMutation(bucketEntry);
  }

  Future<void> _restoreTrashItem(TrashItem item) async {
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) {
      return;
    }
    final sourceListingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.trash(bucketEntry),
    );
    if (!_isCurrentMobileFileManagerRequest(request)) return;
    try {
      await widget.api.restoreTrashItem(
        bucketEntry.config,
        bucketEntry.bucket.name,
        item.id,
        originalKey: item.originalKey,
        isDirectory: item.isDir,
      );
      _invalidateObjectListingCache(bucketId: bucketEntry.id);
      ObjectListingNotifier.instance.markRestored(bucketEntry.bucket.name, [
        item,
      ]);
      if (!_isCurrentTrashMutationSource(
        bucketEntry,
        sourceListingViewGeneration,
      )) {
        return;
      }
      final reloaded = await _reloadBucketTrashAfterMutation(bucketEntry);
      if (!reloaded) return;
      final currentRequest = _captureMobileFileManagerRequest(
        _MobileFileManagerLocation.trash(bucketEntry),
      );
      if (!_isCurrentMobileFileManagerRequest(currentRequest)) return;
      _showPageSnack('已恢复 ${item.name}');
    } catch (error) {
      _invalidateObjectListingCache(bucketId: bucketEntry.id);
      final shouldReport =
          _isCurrentMobileFileManagerRequest(request) &&
          _isCurrentTrashMutationSource(
            bucketEntry,
            sourceListingViewGeneration,
          );
      if (shouldReport) {
        _showPageError(error);
      }
      unawaited(
        _recoverTrashAfterUncertainMutation(
          bucketEntry,
          sourceListingViewGeneration,
        ),
      );
    }
  }

  Future<void> _deleteTrashItemPermanently(TrashItem item) async {
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) {
      return;
    }
    final sourceListingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.trash(bucketEntry),
    );
    if (!_isCurrentTrashMutationCommand(
      bucketEntry,
      sourceListingViewGeneration,
      request,
    )) {
      return;
    }
    final confirmed = await showDeleteTrashItemDialog(context, item);
    if (!confirmed ||
        !_isCurrentTrashMutationCommand(
          bucketEntry,
          sourceListingViewGeneration,
          request,
        )) {
      return;
    }
    try {
      await widget.api.deleteTrashItem(
        bucketEntry.config,
        bucketEntry.bucket.name,
        item.id,
      );
      if (!_isCurrentTrashMutationCommand(
        bucketEntry,
        sourceListingViewGeneration,
        request,
      )) {
        return;
      }
      await _reloadBucketTrashAfterMutation(bucketEntry);
    } catch (error) {
      final shouldReport =
          _isCurrentTrashMutationCommand(
            bucketEntry,
            sourceListingViewGeneration,
            request,
          );
      if (shouldReport) {
        _showPageError(error);
      }
      unawaited(
        _recoverTrashAfterUncertainMutation(
          bucketEntry,
          sourceListingViewGeneration,
        ),
      );
    }
  }

  Future<void> _clearBucketTrash() async {
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null || (_trashItems?.isEmpty ?? true)) {
      return;
    }
    final sourceListingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.trash(bucketEntry),
    );
    if (!_isCurrentTrashMutationCommand(
      bucketEntry,
      sourceListingViewGeneration,
      request,
    )) {
      return;
    }
    final confirmed = await showClearTrashDialog(
      context,
      bucketEntry.bucket.name,
    );
    if (!confirmed ||
        !_isCurrentTrashMutationCommand(
          bucketEntry,
          sourceListingViewGeneration,
          request,
        )) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _selectedObjectKeys.clear();
    });
    try {
      await widget.api.clearTrash(bucketEntry.config, bucketEntry.bucket.name);
      if (!_isCurrentTrashMutationCommand(
        bucketEntry,
        sourceListingViewGeneration,
        request,
      )) {
        return;
      }
      final reloaded = await _reloadBucketTrashAfterMutation(bucketEntry);
      if (!reloaded) return;
      final currentRequest = _captureMobileFileManagerRequest(
        _MobileFileManagerLocation.trash(bucketEntry),
      );
      if (!_isCurrentMobileFileManagerRequest(currentRequest)) return;
      _showPageSnack('已清空 ${bucketEntry.bucket.name} 的回收站');
    } catch (error) {
      final shouldReport =
          _isCurrentTrashMutationCommand(
            bucketEntry,
            sourceListingViewGeneration,
            request,
          );
      if (shouldReport) {
        setState(() => _loading = false);
        _showPageError(error);
      }
      unawaited(
        _recoverTrashAfterUncertainMutation(
          bucketEntry,
          sourceListingViewGeneration,
        ),
      );
    }
  }

  Widget _buildTrashView(ShadThemeData theme) {
    final items = _filteredTrashItems;
    if (items.isEmpty) {
      return FileManagerEmptyState(
        theme: theme,
        icon: LucideIcons.trash2,
        text: _hasSearchQuery ? '当前搜索没有结果' : '此存储桶回收站为空',
      );
    }
    return FileManagerTrashBrowser(
      items: items,
      isGrid: _isGrid,
      scrollController: _contentScrollController,
      hasMore: _trashHasMore,
      loadingMore: _pagingTrash,
      onRestore: (item) => unawaited(_restoreTrashItem(item)),
      onDeletePermanently: (item) =>
          unawaited(_deleteTrashItemPermanently(item)),
    );
  }
}
