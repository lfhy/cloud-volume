// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理分页逻辑：目录对象和桶内回收站都使用触底续载，避免一次性全量拉取。

extension _FileManagerPagePaging on _FileManagerPageState {
  void _maybeLoadMoreContent() {
    if (!_contentScrollController.hasClients) {
      return;
    }
    final position = _contentScrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }
    if (position.pixels < position.maxScrollExtent - 520) {
      return;
    }
    if (_showTrash) {
      unawaited(_loadMoreTrashItems());
      return;
    }
    if (_activeBucket != null && !_isTrashHome) {
      unawaited(_loadMoreObjects());
    }
  }

  Future<void> _loadMoreObjects() async {
    if (_loading ||
        _pagingObjects ||
        !_objectsHasMore ||
        _activeBucket == null ||
        _showTrash) {
      return;
    }
    final bucketEntry = _activeBucketEntry!;
    final prefix = _prefix;
    final nextToken = _objectsNextToken;
    final listingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
    );
    bool isCurrentRequest() =>
        _isCurrentListingViewRequest(listingViewGeneration) &&
        _isCurrentMobileFileManagerRequest(request);
    if (!isCurrentRequest()) return;
    setState(() => _pagingObjects = true);
    try {
      final page = await _listObjectPageCached(
        bucketEntry,
        prefix,
        nextToken,
        _FileManagerPageState._listPageSize,
        mobileRequest: request,
        requestStillCurrent: isCurrentRequest,
        listingViewGeneration: listingViewGeneration,
      );
      if (!mounted || !isCurrentRequest()) {
        return;
      }
      setState(() {
        _objects = <ObjectInfo>[...?_objects, ...page.items];
        _objectsNextToken = page.nextToken;
        _objectsHasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted || !isCurrentRequest()) {
        return;
      }
      _showPageError(error);
    } finally {
      if (mounted && isCurrentRequest()) {
        setState(() => _pagingObjects = false);
      }
    }
  }

  Future<void> _loadMoreTrashItems() async {
    if (_loading ||
        _pagingTrash ||
        !_trashHasMore ||
        _activeBucket == null ||
        !_showTrash) {
      return;
    }
    final bucketEntry = _activeBucketEntry!;
    final nextToken = _trashNextToken;
    final listingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.trash(bucketEntry),
    );
    bool isCurrentRequest() =>
        _isCurrentListingViewRequest(listingViewGeneration) &&
        _isCurrentMobileFileManagerRequest(request);
    if (!isCurrentRequest()) return;
    setState(() => _pagingTrash = true);
    try {
      final page = await widget.api.listTrashPage(
        bucketEntry.config,
        bucketEntry.bucket.name,
        nextToken,
        _FileManagerPageState._trashPageSize,
      );
      if (!mounted || !isCurrentRequest()) {
        return;
      }
      setState(() {
        final merged = <TrashItem>[...?_trashItems, ...page.items];
        merged.sort((left, right) => right.deletedAt.compareTo(left.deletedAt));
        _trashItems = merged;
        _trashNextToken = page.nextToken;
        _trashHasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted || !isCurrentRequest()) {
        return;
      }
      _showPageError(error);
    } finally {
      if (mounted && isCurrentRequest()) {
        setState(() => _pagingTrash = false);
      }
    }
  }
}
