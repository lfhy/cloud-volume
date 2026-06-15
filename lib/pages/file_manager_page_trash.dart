// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页回收站逻辑：按 bucket 浏览、恢复和彻底删除软删除对象。

extension _FileManagerPageTrash on _FileManagerPageState {
  Future<bool> _openBucketTrash([FileManagerBucketEntry? bucket]) async {
    final targetBucket = bucket ?? _activeBucketEntry;
    if (targetBucket == null) {
      return false;
    }
    _beginLoading(message: '加载回收站...');
    try {
      final page = await widget.api.listTrashPage(
        targetBucket.config,
        targetBucket.bucket.name,
        '',
        _FileManagerPageState._trashPageSize,
      );
      if (!mounted) return false;
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
      if (!mounted) return false;
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

  Future<void> _restoreTrashItem(TrashItem item) async {
    if (_activeBucket == null) {
      return;
    }
    try {
      await widget.api.restoreTrashItem(_activeConfig, _activeBucket!, item.id);
      ObjectListingNotifier.instance.markRestored(_activeBucket!, [item]);
      if (!mounted) return;
      await _openBucketTrash(_activeBucketEntry!);
      _showPageSnack('已恢复 ${item.name}');
    } catch (error) {
      _showPageError(error);
    }
  }

  Future<void> _deleteTrashItemPermanently(TrashItem item) async {
    if (_activeBucket == null) {
      return;
    }
    final confirmed = await showDeleteTrashItemDialog(context, item);
    if (!confirmed) {
      return;
    }
    try {
      await widget.api.deleteTrashItem(_activeConfig, _activeBucket!, item.id);
      if (!mounted) return;
      await _openBucketTrash(_activeBucketEntry!);
    } catch (error) {
      _showPageError(error);
    }
  }

  Future<void> _clearBucketTrash() async {
    final bucket = _activeBucket;
    if (bucket == null || (_trashItems?.isEmpty ?? true)) {
      return;
    }
    final confirmed = await showClearTrashDialog(context, bucket);
    if (!confirmed) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _selectedObjectKeys.clear();
    });
    try {
      await widget.api.clearTrash(_activeConfig, bucket);
      if (!mounted) return;
      await _openBucketTrash(_activeBucketEntry!);
      _showPageSnack('已清空 $bucket 的回收站');
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showPageError(error);
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
