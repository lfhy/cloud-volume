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
    _pagingObjects = true;
    try {
      final page = await _listObjectPageCached(
        _activeBucketEntry!,
        _prefix,
        _objectsNextToken,
        _FileManagerPageState._listPageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _objects = <ObjectInfo>[...?_objects, ...page.items];
        _objectsNextToken = page.nextToken;
        _objectsHasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showPageError(error);
    } finally {
      _pagingObjects = false;
      if (mounted) {
        setState(() {});
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
    _pagingTrash = true;
    try {
      final page = await widget.api.listTrashPage(
        _activeConfig,
        _activeBucket!,
        _trashNextToken,
        _FileManagerPageState._trashPageSize,
      );
      if (!mounted) {
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
      if (!mounted) {
        return;
      }
      _showPageError(error);
    } finally {
      _pagingTrash = false;
      if (mounted) {
        setState(() {});
      }
    }
  }
}
