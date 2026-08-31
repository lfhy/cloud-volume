part of 'file_manager_page.dart';

// 文件管理页派生状态：把筛选和当前视图相关计算单独拆出，避免主文件过长。

extension _FileManagerPageDerivedState on _FileManagerPageState {
  /// Every primary listing changes this generation so a late bucket, object,
  /// trash, or pagination response cannot take over a newer view.
  int _beginListingViewRequest() {
    final generation = ++_listingViewGeneration;
    if (widget.viewBuilder != null) {
      // Mutations retain this generation. Unlike navigation, input generation
      // changes only for fresh bootstrap/profile data and rejects old configs.
      _mobileInputGenerationByListingView[generation] = _mobileInputGeneration;
      if (_mobileInputGenerationByListingView.length > 64) {
        _mobileInputGenerationByListingView.removeWhere(
          (key, _) => key < generation - 64,
        );
      }
    }
    return generation;
  }

  bool _isCurrentListingViewRequest(int generation) =>
      generation == _listingViewGeneration;

  _MobileFileManagerRequest? _captureMobileFileManagerRequest(
    _MobileFileManagerLocation location, {
    int? epoch,
  }) {
    if (widget.viewBuilder == null) return null;
    return _MobileFileManagerRequest(
      location: location,
      epoch: epoch ?? _mobileNavigationEpoch,
      inputGeneration: _mobileInputGeneration,
    );
  }

  bool _isCurrentMobileFileManagerRequest(_MobileFileManagerRequest? request) =>
      request == null || request.isCurrent(this);

  /// A confirmation sheet can outlive an Android input refresh. Keep its
  /// captured entry from issuing a write after the bucket ID was rebound to a
  /// different config/root prefix.
  bool _isCurrentObjectMutationCommand(
    FileManagerBucketEntry bucketEntry,
    String prefix,
    int sourceListingViewGeneration,
    _MobileFileManagerRequest? request,
  ) {
    return _isCurrentMobileFileManagerRequest(request) &&
        _isCurrentObjectMutationSource(
          bucketEntry,
          prefix,
          sourceListingViewGeneration,
        );
  }

  /// Same command-level guard for destructive recycle-bin actions.
  bool _isCurrentTrashMutationCommand(
    FileManagerBucketEntry bucketEntry,
    int sourceListingViewGeneration,
    _MobileFileManagerRequest? request,
  ) {
    return _isCurrentMobileFileManagerRequest(request) &&
        _isCurrentTrashMutationSource(bucketEntry, sourceListingViewGeneration);
  }

  /// Bucket-list sheets do not have an object/trash location to validate.
  /// Identity plus input generation makes an old configuration unusable after
  /// Android refreshes its profile-derived entries.
  bool _isCurrentMobileBucketEntry(
    FileManagerBucketEntry bucketEntry,
    int inputGeneration,
  ) {
    if (widget.viewBuilder == null) return true;
    return !_mobileInputRefreshNeedsRebind &&
        inputGeneration == _mobileInputGeneration &&
        (_buckets?.any((entry) => identical(entry, bucketEntry)) ?? false);
  }

  /// Bucket-level dialogs can outlive a listing refresh as well. The listing
  /// generation closes that gap before the refreshed entries replace the old
  /// list, while identity rejects a completed Android input rebind.
  bool _isCurrentBucketCommand(
    FileManagerBucketEntry bucketEntry,
    int sourceListingViewGeneration,
    int inputGeneration,
  ) {
    if (!mounted || !_isCurrentListingViewRequest(sourceListingViewGeneration)) {
      return false;
    }
    if (widget.viewBuilder != null) {
      return _isCurrentMobileBucketEntry(bucketEntry, inputGeneration);
    }
    return identical(_activeBucketEntry, bucketEntry) ||
        (_buckets?.any((entry) => identical(entry, bucketEntry)) ?? false);
  }

  void _reconfigureUnavailableBucketSource(String profileName) {
    // The account-management page is the single repair surface for a source.
    widget.onOpenAccountManagement?.call();
  }

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
