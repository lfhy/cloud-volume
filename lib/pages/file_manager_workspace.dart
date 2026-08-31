part of 'file_manager_page.dart';

/// Lets a platform page render the shared file-browser state with its own UI.
typedef FileManagerWorkspaceViewBuilder =
    Widget Function(
      BuildContext context,
      FileManagerWorkspaceController workspace,
    );

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
  final VoidCallback? onPendingSyncRemoteOpenConsumed;
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
  bool get canNavigateBack => hasActiveBucket;
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

  Future<bool> handleSystemBack() async {
    if (!hasActiveBucket) return false;
    await navigateBack();
    return true;
  }

  Future<void> navigateBack() =>
      isShowingTrash ? _state._closeBucketTrash() : _state._navUp();

  Future<void> refresh() {
    final active = _state._activeBucketEntry;
    if (active == null) return _state._loadBuckets(force: true);
    if (isShowingTrash) return _state._openBucketTrash(active);
    return _state._loadObjects(active, _state._prefix, forceRefresh: true);
  }

  Future<void> openBucket(FileManagerBucketEntry bucket) =>
      _state._navToBucket(bucket);
  Future<void> openDirectory(String prefix) => _state._navToPrefix(prefix);
  Future<void> openFile(ObjectInfo object) => _state._openObject(object);
  Future<void> openTrash([FileManagerBucketEntry? bucket]) =>
      _state._openBucketTrash(bucket);
  Future<void> closeTrash() => _state._closeBucketTrash();
  Future<void> clearTrash() => _state._clearBucketTrash();
  Future<void> configureBucket(FileManagerBucketEntry bucket) =>
      _state._configureBucket(bucket);
  bool bucketTrashEnabled(FileManagerBucketEntry bucket) =>
      _state._bucketTrashEnabled(bucket);
  Future<void> upload() => _state._upload();
  Future<void> createDirectory() => _state._createDirectory();
  Future<void> downloadSelected() => _state._downloadSelectedObjects();
  Future<void> deleteSelected() => _state._deleteSelectedObjects();
  void clearSelection() => _state._clearSelection();
  void toggleSelection(ObjectInfo object) =>
      _state._toggleObjectSelection(object);
  Future<void> performObjectAction(
    ObjectInfo object,
    FileObjectAction action,
  ) => _state._handleObjectAction(object, action);
  Future<void> restoreTrashItem(TrashItem item) =>
      _state._restoreTrashItem(item);
  Future<void> deleteTrashItemPermanently(TrashItem item) =>
      _state._deleteTrashItemPermanently(item);
  void openAccountManagement() => _state.widget.onOpenAccountManagement?.call();
}
