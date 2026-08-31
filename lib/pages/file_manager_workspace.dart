// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

/// Lets a platform page render the shared file-browser state with its own UI.
typedef FileManagerWorkspaceViewBuilder =
    Widget Function(
      BuildContext context,
      FileManagerWorkspaceController workspace,
    );

/// A logical Android file location. It is committed before a remote request
/// completes so Back can return from loading and error states as well.
enum _MobileFileManagerLocationKind { bucketList, objects, trash }

class _MobileFileManagerLocation {
  const _MobileFileManagerLocation._(
    this.kind, {
    this.bucket,
    this.prefix = '',
  });

  const _MobileFileManagerLocation.bucketList()
    : this._(_MobileFileManagerLocationKind.bucketList);

  const _MobileFileManagerLocation.objects(
    FileManagerBucketEntry bucket,
    String prefix,
  ) : this._(
        _MobileFileManagerLocationKind.objects,
        bucket: bucket,
        prefix: prefix,
      );

  const _MobileFileManagerLocation.trash(FileManagerBucketEntry bucket)
    : this._(_MobileFileManagerLocationKind.trash, bucket: bucket);

  final _MobileFileManagerLocationKind kind;
  final FileManagerBucketEntry? bucket;
  final String prefix;

  bool matches(_MobileFileManagerLocation other) {
    return kind == other.kind &&
        bucket?.id == other.bucket?.id &&
        prefix == other.prefix;
  }
}

/// Couples a mobile listing request to the location that started it.
class _MobileFileManagerRequest {
  const _MobileFileManagerRequest({
    required this.location,
    required this.epoch,
    required this.inputGeneration,
  });

  final _MobileFileManagerLocation location;
  final int epoch;
  final int inputGeneration;

  bool isCurrent(_FileManagerPageState state) =>
      epoch == state._mobileNavigationEpoch &&
      inputGeneration == state._mobileInputGeneration &&
      state._mobileLocation.matches(location);
}

/// Rebound Android locations retain only buckets resolved from fresh inputs.
class _ReboundMobileFileManagerLocations {
  const _ReboundMobileFileManagerLocations({
    required this.current,
    required this.history,
  });

  final _MobileFileManagerLocation current;
  final List<_MobileFileManagerLocation> history;
}

/// Shared file-browser runtime. It owns loading and mutations, but not a
/// platform's chrome: desktop uses the default renderer and Android supplies
/// [viewBuilder] from its dedicated page.
class FileManagerWorkspace extends StatefulWidget {
  const FileManagerWorkspace({
    super.key,
    required this.api,
    required this.config,
    required this.profiles,
    required this.onRefresh,
    this.homeView = FileManagerHomeView.files,
    this.pendingSyncRemoteOpen,
    this.pendingSyncRemoteOpenGeneration = 0,
    this.onPendingSyncRemoteOpenConsumed,
    this.onOpenAccountManagement,
    this.viewBuilder,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final List<ProfileInfo> profiles;
  final VoidCallback onRefresh;
  final FileManagerHomeView homeView;
  final SyncRemoteOpenRequest? pendingSyncRemoteOpen;
  final int pendingSyncRemoteOpenGeneration;
  final SyncRemoteOpenConsumer? onPendingSyncRemoteOpenConsumed;
  final VoidCallback? onOpenAccountManagement;
  final FileManagerWorkspaceViewBuilder? viewBuilder;

  @override
  State<FileManagerWorkspace> createState() => _FileManagerPageState();
}

/// Public, read-only view of the shared workspace plus its user actions.
///
/// It deliberately exposes no desktop widgets. A mobile page can choose its
/// own hierarchy while uploads, destructive operations, and navigation retain
/// the one established implementation.
class FileManagerWorkspaceController {
  const FileManagerWorkspaceController._(this._state);

  final _FileManagerPageState _state;

  TextEditingController get searchController => _state._searchController;
  ScrollController get contentScrollController =>
      _state._contentScrollController;
  bool get isLoading => _state._loading;
  String get loadingMessage => _state._loadingMessage;
  String? get loadingDetail => _state._loadingDetail;
  String? get error => _state._error;
  bool get isShowingTrash => _state._showTrash;
  bool get isTrashHome => _state._isTrashHome;
  bool get hasActiveBucket => _state._activeBucketEntry != null;
  bool get isAtBucketRoot => _state._prefix.isEmpty;
  bool get hasSearchQuery => _state._hasSearchQuery;
  bool get currentDirectoryWritable => _state._currentDirectoryWritable;
  bool get currentBucketWritable => _state._currentBucketWritable;
  bool get activeBucketTrashEnabled => _state._activeBucketTrashEnabled;
  bool get activeBucketReadOnly => _state._activeBucketReadOnly;
  bool get supportsDirectoryDownload =>
      _state.widget.api.capabilities.supportsDownloadDirectory;
  bool get supportsShareLinks => _state._activeConfig.supportsShareLinks;
  bool get canOpenAccountManagement =>
      _state.widget.onOpenAccountManagement != null;
  bool get hasTrashItems => _state._trashItems?.isNotEmpty ?? false;
  bool get hasSelectedObjects => _state._selectedObjectKeys.isNotEmpty;
  bool get hasPendingSyncRemoteOpen =>
      _state._activeMobileSyncRemoteOpen != null;
  bool get canNavigateBack => _state._canHandleMobileFileManagerBack;
  bool get isInputRebindPending =>
      _state._mobileInputRefreshNeedsRebind ||
      _state._mobileInputRebind != null;
  bool get objectsHasMore => _state._objectsHasMore;
  bool get pagingObjects => _state._pagingObjects;
  bool get trashHasMore => _state._trashHasMore;
  bool get pagingTrash => _state._pagingTrash;
  int get unavailableSourceCount => _state._unavailableBucketSources.length;

  List<FileManagerBucketEntry> get buckets => _state._filteredBuckets;
  List<TrashItem> get trashItems => _state._filteredTrashItems;
  FileManagerBucketEntry? get activeBucketEntry => _state._activeBucketEntry;
  List<String> get breadcrumbs =>
      List<String>.unmodifiable(_state._breadcrumbs);
  List<ObjectInfo> get visibleObjects => _state._filteredVisibleObjects;
  Set<String> get selectedObjectKeys =>
      Set<String>.unmodifiable(_state._selectedObjectKeys);
  List<ObjectInfo> get selectedObjects => _state._selectedObjects;

  Future<bool> handleSystemBack() => _state._handleMobileFileManagerBack();

  Future<void> navigateBack() async => await handleSystemBack();

  Future<void> refresh() async {
    if (_state._mobileInputRefreshNeedsRebind &&
        _state._mobileInputRebind == null) {
      _state._scheduleMobileFileManagerInputRebind();
    }
    if (!await _state._ensureMobileFileManagerInputRebound()) return;
    await _state._loadMobileFileManagerLocation(
      _state._mobileLocation,
      forceRefresh: true,
    );
  }

  Future<void> openBucket(FileManagerBucketEntry bucket) async {
    final inputGeneration = _state._mobileInputGeneration;
    if (!await _hasCurrentMobileInput(inputGeneration)) return;
    final currentBucket = _bucketById(bucket.id);
    if (currentBucket == null) return;
    await _pushAndLoad(_MobileFileManagerLocation.objects(currentBucket, ''));
  }

  Future<void> openDirectory(String prefix) async {
    final bucket = _state._activeBucketEntry;
    if (bucket == null ||
        !await _canUseMobileLocation(
          _MobileFileManagerLocation.objects(bucket, _state._prefix),
        )) {
      return;
    }
    await _pushAndLoad(_MobileFileManagerLocation.objects(bucket, prefix));
  }

  Future<void> openFile(ObjectInfo object) async {
    final bucket = _state._activeBucketEntry;
    if (bucket == null ||
        !await _canUseMobileLocation(
          _MobileFileManagerLocation.objects(bucket, _state._prefix),
        )) {
      return;
    }
    await _state._openObject(object);
  }

  Future<void> openTrash([FileManagerBucketEntry? bucket]) async {
    final target = bucket ?? _state._activeBucketEntry;
    if (target == null) return;
    final inputGeneration = _state._mobileInputGeneration;
    if (!await _hasCurrentMobileInput(inputGeneration)) return;
    final currentBucket = _bucketById(target.id);
    if (currentBucket == null) return;
    await _pushAndLoad(_MobileFileManagerLocation.trash(currentBucket));
  }

  Future<void> closeTrash() async {
    final location = _state._mobileLocation;
    if (!await _canUseMobileLocation(location)) return;
    if (_state._mobileLocationHistory.isNotEmpty) {
      await navigateBack();
      return;
    }
    await _state._closeBucketTrash();
  }

  Future<void> clearTrash() async {
    final bucket = _state._activeBucketEntry;
    if (bucket == null ||
        !await _canUseMobileLocation(
          _MobileFileManagerLocation.trash(bucket),
        )) {
      return;
    }
    await _state._clearBucketTrash();
  }

  Future<void> configureBucket(FileManagerBucketEntry bucket) async {
    final inputGeneration = _state._mobileInputGeneration;
    if (!await _hasCurrentMobileInput(inputGeneration)) return;
    final currentBucket = _bucketById(bucket.id);
    if (currentBucket == null) return;
    await _state._configureBucket(currentBucket);
  }

  bool bucketTrashEnabled(FileManagerBucketEntry bucket) =>
      _state._bucketTrashEnabled(bucket);
  Future<void> upload() async {
    if (!await _canUseActiveObjectLocation()) return;
    await _state._upload();
  }

  Future<void> createDirectory() async {
    if (!await _canUseActiveObjectLocation()) return;
    await _state._createDirectory();
  }

  Future<void> downloadSelected() async {
    if (!await _canUseActiveObjectLocation()) return;
    await _state._downloadSelectedObjects();
  }

  Future<void> deleteSelected() async {
    if (!await _canUseActiveObjectLocation()) return;
    await _state._deleteSelectedObjects();
  }

  void clearSelection() => _state._clearSelection();
  void toggleSelection(ObjectInfo object) =>
      _state._toggleObjectSelection(object);
  Future<void> performObjectAction(
    ObjectInfo object,
    FileObjectAction action,
  ) async {
    if (!await _canUseActiveObjectLocation()) return;
    if (action == FileObjectAction.open && object.isDir) {
      await openDirectory(object.key);
      return;
    }
    await _state._handleObjectAction(object, action);
  }

  Future<void> restoreTrashItem(TrashItem item) async {
    final bucket = _state._activeBucketEntry;
    if (bucket == null ||
        !await _canUseMobileLocation(
          _MobileFileManagerLocation.trash(bucket),
        )) {
      return;
    }
    await _state._restoreTrashItem(item);
  }

  Future<void> deleteTrashItemPermanently(TrashItem item) async {
    final bucket = _state._activeBucketEntry;
    if (bucket == null ||
        !await _canUseMobileLocation(
          _MobileFileManagerLocation.trash(bucket),
        )) {
      return;
    }
    await _state._deleteTrashItemPermanently(item);
  }

  void openAccountManagement() => _state.widget.onOpenAccountManagement?.call();

  Future<void> _pushAndLoad(_MobileFileManagerLocation target) async {
    await _state._pushAndLoadMobileFileManagerLocation(target);
  }

  FileManagerBucketEntry? _bucketById(String id) {
    for (final bucket in _state._buckets ?? const <FileManagerBucketEntry>[]) {
      if (bucket.id == id) return bucket;
    }
    return null;
  }

  Future<bool> _canUseActiveObjectLocation() {
    final bucket = _state._activeBucketEntry;
    if (bucket == null) return Future<bool>.value(false);
    return _canUseMobileLocation(
      _MobileFileManagerLocation.objects(bucket, _state._prefix),
    );
  }

  Future<bool> _canUseMobileLocation(
    _MobileFileManagerLocation expected,
  ) async {
    final inputGeneration = _state._mobileInputGeneration;
    if (!await _hasCurrentMobileInput(inputGeneration)) return false;
    return _state._mobileLocation.matches(expected) &&
        (expected.bucket == null ||
            identical(_state._mobileLocation.bucket, expected.bucket));
  }

  Future<bool> _hasCurrentMobileInput(int inputGeneration) async {
    return await _state._ensureMobileFileManagerInputRebound() &&
        inputGeneration == _state._mobileInputGeneration;
  }
}

/// Owns Android's logical file-location transitions independently of either
/// presentation. It is also used by external navigation such as sync tasks.
extension _FileManagerPageMobileNavigation on _FileManagerPageState {
  bool get _canHandleMobileFileManagerBack =>
      _activeMobileSyncRemoteOpen != null || _mobileLocationHistory.isNotEmpty;

  Future<bool> _handleMobileFileManagerBack() async {
    if (_cancelPendingMobileSyncRemoteOpen()) return true;
    return await _navigateBackMobileFileManagerLocation();
  }

  Future<bool> _pushAndLoadMobileFileManagerLocation(
    _MobileFileManagerLocation target,
  ) async {
    if (!await _ensureMobileFileManagerInputRebound()) return false;
    final targetAfterRebind = _rebindMobileFileManagerLocation(
      target,
      <String, FileManagerBucketEntry>{
        for (final entry in _buckets ?? const <FileManagerBucketEntry>[])
          entry.id: entry,
      },
    );
    if (targetAfterRebind == null) return false;
    final current = _mobileLocation;
    if (!current.matches(targetAfterRebind)) {
      _mobileLocationHistory.add(current);
      _mobileLocation = targetAfterRebind;
    }
    return await _loadMobileFileManagerLocation(targetAfterRebind);
  }

  Future<bool> _navigateBackMobileFileManagerLocation() async {
    // Do not let Back consume history using the previous profile's bucket
    // entry while a bootstrap refresh is still rebinding it.
    if (!await _ensureMobileFileManagerInputRebound()) return true;
    final history = _mobileLocationHistory;
    if (history.isEmpty) return false;
    final previous = history.removeLast();
    _mobileLocation = previous;
    await _loadMobileFileManagerLocation(previous);
    return true;
  }

  Future<bool> _loadMobileFileManagerLocation(
    _MobileFileManagerLocation location, {
    bool forceRefresh = false,
    int? inputGeneration,
  }) async {
    if (widget.viewBuilder != null && inputGeneration == null) {
      if (!await _ensureMobileFileManagerInputRebound()) return false;
    }
    if (inputGeneration != null && inputGeneration != _mobileInputGeneration) {
      return false;
    }
    if (widget.viewBuilder != null) {
      final rebound = _rebindMobileFileManagerLocation(
        location,
        <String, FileManagerBucketEntry>{
          for (final entry in _buckets ?? const <FileManagerBucketEntry>[])
            entry.id: entry,
        },
      );
      if (rebound == null) return false;
      if (_mobileLocation.matches(location) &&
          !identical(_mobileLocation.bucket, rebound.bucket)) {
        _mobileLocation = rebound;
      }
      location = rebound;
    }
    final epoch = ++_mobileNavigationEpoch;
    return await switch (location.kind) {
      _MobileFileManagerLocationKind.bucketList => _loadBuckets(
        force: forceRefresh,
        mobileNavigationEpoch: epoch,
      ),
      _MobileFileManagerLocationKind.objects => _loadObjects(
        location.bucket!,
        location.prefix,
        forceRefresh: forceRefresh,
        mobileNavigationEpoch: epoch,
      ),
      _MobileFileManagerLocationKind.trash => _openBucketTrash(
        bucket: location.bucket!,
        mobileNavigationEpoch: epoch,
      ),
    };
  }

  /// Starts a same-location reload that must invalidate older pagination.
  /// Callers verify [request] first; desktop has no mobile request and keeps
  /// its established reload behavior.
  _MobileFileManagerRequest? _supersedeMobileFileManagerRequest(
    _MobileFileManagerRequest? request,
  ) {
    if (request == null) return null;
    assert(_isCurrentMobileFileManagerRequest(request));
    return _MobileFileManagerRequest(
      location: request.location,
      epoch: ++_mobileNavigationEpoch,
      inputGeneration: request.inputGeneration,
    );
  }
}
