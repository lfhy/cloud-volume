part of 'file_manager_page.dart';

// 文件管理页派生状态：把筛选和当前视图相关计算单独拆出，避免主文件过长。

extension _FileManagerPageDerivedState on _FileManagerPageState {
  String? get _activeBucket => _activeBucketEntry?.bucket.name;

  String? get _activeBucketLabel => _activeBucketEntry?.label;

  String? get _activeBucketId => _activeBucketEntry?.id;

  RemoteStorageConfig get _activeConfig =>
      _activeBucketEntry?.config ?? widget.config;

  /// Desktop profiles with an immutable identity are handled by the Go
  /// metadata journal; their Dart producer remains execution-only.
  bool get _usesMetadataRemoteTasks =>
      widget.api.capabilities.supportsMounts &&
      _activeConfig.profileId.trim().isNotEmpty;

  BucketMountStatus? get _activeMountStatus =>
      _activeBucketId == null ? null : _bucketMountStatuses[_activeBucketId!];

  bool get _isTrashHome => widget.homeView == FileManagerHomeView.trash;

  bool get _acceptsFileTransferInput =>
      !_loading && !_showTrash && _activeBucket != null;

  bool get _hasSearchQuery => _searchText.isNotEmpty;

  List<FileManagerBucketEntry> get _filteredBuckets {
    final buckets = _buckets ?? const <FileManagerBucketEntry>[];
    if (!_hasSearchQuery) {
      return buckets;
    }
    return buckets
        .where(
          (bucket) =>
              bucket.label.toLowerCase().contains(_searchText) ||
              bucket.sourceLabel.toLowerCase().contains(_searchText),
        )
        .toList(growable: false);
  }

  List<ObjectInfo> get _filteredVisibleObjects {
    final visibleObjects = _visibleSelectableObjects;
    if (!_hasSearchQuery) {
      return visibleObjects;
    }
    return visibleObjects
        .where(
          (object) =>
              object.displayName.toLowerCase().contains(_searchText) ||
              object.key.toLowerCase().contains(_searchText),
        )
        .toList(growable: false);
  }

  List<TrashItem> get _filteredTrashItems {
    final items = _trashItems ?? const <TrashItem>[];
    if (!_hasSearchQuery) {
      return items;
    }
    return items
        .where(
          (item) =>
              item.name.toLowerCase().contains(_searchText) ||
              item.originalKey.toLowerCase().contains(_searchText),
        )
        .toList(growable: false);
  }
}
