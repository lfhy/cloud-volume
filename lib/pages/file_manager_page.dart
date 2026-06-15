// 文件管理页：负责面包屑导航、桶/对象浏览，以及上传下载交互。

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/services/file_access_service.dart';
import 'package:remote_storage/services/file_access_transfer_request.dart';
import 'package:remote_storage/services/desktop_file_transfer_service.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/bucket_settings_dialog.dart';
import 'package:remote_storage/state/object_listing_notifier.dart';
import 'package:remote_storage/state/share_records_notifier.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/utils/object_visibility.dart';
import 'package:remote_storage/widgets/create_directory_dialog.dart';
import 'package:remote_storage/widgets/file_manager_action_bar.dart';
import 'package:remote_storage/widgets/file_manager_breadcrumb_bar.dart';
import 'package:remote_storage/widgets/file_manager_bucket_browser.dart';
import 'package:remote_storage/widgets/file_manager_empty_state.dart';
import 'package:remote_storage/widgets/file_manager_error_view.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:remote_storage/widgets/file_manager_trash_browser.dart';
import 'package:remote_storage/widgets/file_preview_dialog.dart';
import 'package:remote_storage/widgets/file_transfer_clipboard_region.dart';
import 'package:remote_storage/widgets/mount_bucket_dialog.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:remote_storage/widgets/share_dialogs.dart';
import 'package:remote_storage/widgets/batch_task_progress_dialog.dart';
import 'package:remote_storage/widgets/batch_task_progress_mode.dart';
import 'package:remote_storage/utils/file_preview_type.dart';
import 'package:path/path.dart' as path;
import 'package:shadcn_ui/shadcn_ui.dart';

part 'file_manager_page_actions.dart';
part 'file_manager_page_access.dart';
part 'file_manager_page_bucket_policy.dart';
part 'file_manager_page_bucket_view.dart';
part 'file_manager_page_mount.dart';
part 'file_manager_page_object_loading.dart';
part 'file_manager_page_object_deletes.dart';
part 'file_manager_page_paging.dart';
part 'file_manager_page_preview.dart';
part 'file_manager_page_restore_sync.dart';
part 'file_manager_page_selected_actions.dart';
part 'file_manager_page_state.dart';
part 'file_manager_page_selection.dart';
part 'file_manager_page_sources.dart';
part 'file_manager_page_transfer_inputs.dart';
part 'file_manager_page_trash.dart';
part 'file_manager_page_upload_feedback.dart';
part 'file_manager_page_webdav.dart';

// 文件管理页首页模式：既支持普通文件浏览，也支持侧边栏独立回收站入口。
enum FileManagerHomeView { files, trash }

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({
    super.key,
    required this.api,
    required this.config,
    required this.profiles,
    required this.onEditConfig,
    required this.onRefresh,
    this.homeView = FileManagerHomeView.files,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final List<ProfileInfo> profiles;
  final VoidCallback onEditConfig;
  final VoidCallback onRefresh;
  final FileManagerHomeView homeView;

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  static const double _gridIconSize = 68;
  static const double _listIconSize = 20;
  static const double _bucketGridIconSize = 72;
  static const Duration _mountStatusRefreshInterval = Duration(seconds: 4);
  static const Duration _loadingDetailDelay = Duration(seconds: 2);
  static const int _listPageSize = 200;
  static const int _trashPageSize = 80;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _contentScrollController = ScrollController();
  List<FileManagerBucketEntry>? _buckets;
  FileManagerBucketEntry? _activeBucketEntry;
  List<ObjectInfo>? _objects;
  List<TrashItem>? _trashItems;
  String _prefix = '';
  List<String> _breadcrumbs = [];
  bool _loading = false;
  String _loadingMessage = '加载中...';
  String? _loadingDetail;
  String? _error;
  bool _isGrid = false;
  bool _showTrash = false;
  String _searchText = '';
  final Map<String, BucketMountStatus> _bucketMountStatuses =
      <String, BucketMountStatus>{};
  final Set<String> _mountBusyBuckets = <String>{};
  final Set<String> _selectedObjectKeys = <String>{};
  final Set<String> _deletingObjectKeys = <String>{};
  final Map<_ObjectListingCacheKey, ObjectListPage> _objectListingCache =
      <_ObjectListingCacheKey, ObjectListPage>{};
  Timer? _loadingDetailTimer;
  Timer? _mountStatusRefreshTimer;
  bool _mountStatusRefreshInFlight = false;
  String _objectsNextToken = '';
  bool _objectsHasMore = false;
  bool _pagingObjects = false;
  DirectoryAccess? _directoryAccess;
  bool _checkingDirectoryAccess = false;
  String _trashNextToken = '';
  bool _trashHasMore = false;
  bool _pagingTrash = false;
  int _seenObjectListingMutationVersion = 0;
  final Map<String, _PendingUploadRefresh> _pendingUploadRefreshes =
      <String, _PendingUploadRefresh>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
    _contentScrollController.addListener(_maybeLoadMoreContent);
    ObjectListingNotifier.instance.addListener(_handleObjectListingMutation);
    TransferQueue.instance.addListener(_handleUploadTaskRefresh);
    _startMountStatusRefreshTimer();
    _loadBuckets();
  }

  @override
  void dispose() {
    _loadingDetailTimer?.cancel();
    _mountStatusRefreshTimer?.cancel();
    ObjectListingNotifier.instance.removeListener(_handleObjectListingMutation);
    TransferQueue.instance.removeListener(_handleUploadTaskRefresh);
    _contentScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FileManagerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config ||
        oldWidget.profiles != widget.profiles) {
      unawaited(_loadBuckets());
    }
  }

  Future<bool> _loadBuckets() async {
    _beginLoading(message: '加载存储桶...');
    try {
      final bucketEntries = await _loadBucketEntries();
      if (!mounted) return false;
      setState(() {
        _objectListingCache.clear();
        _buckets = bucketEntries;
        _activeBucketEntry = null;
        _objects = null;
        _trashItems = null;
        _prefix = '';
        _breadcrumbs = [];
        _showTrash = false;
        _objectsNextToken = '';
        _objectsHasMore = false;
        _pagingObjects = false;
        _directoryAccess = null;
        _checkingDirectoryAccess = false;
        _trashNextToken = '';
        _trashHasMore = false;
        _pagingTrash = false;
        _bucketMountStatuses.clear();
        _mountBusyBuckets.clear();
        _selectedObjectKeys.clear();
        _deletingObjectKeys.clear();
        _endLoading();
      });
      if (_contentScrollController.hasClients) {
        _contentScrollController.jumpTo(0);
      }
      if (bucketEntries.isNotEmpty) {
        unawaited(_refreshBucketMountStatuses(bucketEntries));
      }
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

  void _startMountStatusRefreshTimer() {
    _mountStatusRefreshTimer?.cancel();
    ObjectListingNotifier.instance.removeListener(_handleObjectListingMutation);
    if (!widget.api.capabilities.supportsMounts) {
      return;
    }
    _mountStatusRefreshTimer = Timer.periodic(
      _mountStatusRefreshInterval,
      (_) => unawaited(_refreshVisibleMountStatuses()),
    );
  }

  void _beginLoading({String message = '加载中...', String? delayedDetail}) {
    _loadingDetailTimer?.cancel();
    setState(() {
      _loading = true;
      _loadingMessage = message;
      _loadingDetail = null;
      _error = null;
    });
    if (delayedDetail == null) {
      return;
    }
    _loadingDetailTimer = Timer(_loadingDetailDelay, () {
      if (!mounted || !_loading) {
        return;
      }
      setState(() => _loadingDetail = delayedDetail);
    });
  }

  void _endLoading() {
    _loadingDetailTimer?.cancel();
    _loadingDetailTimer = null;
    _loading = false;
    _loadingDetail = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 32, right: 32, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          const SizedBox(height: 16),
          Expanded(
            child: FileTransferClipboardRegion(
              enabled: _acceptsFileTransferInput,
              acceptsLocalFiles: _currentDirectoryWritable,
              onPasteLocalFiles: (paths) => unawaited(_uploadLocalPaths(paths)),
              onCopySelection: () =>
                  unawaited(_copySelectedObjectsToClipboard()),
              child: _buildContentWithMountLoading(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isTrashHome) ...[
          Text(
            '回收站',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _showTrash ? '管理当前存储桶中的已删除对象。' : '选择一个存储桶进入它的回收站。',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
        ],
        FileManagerBreadcrumbBar(
          theme: theme,
          activeBucket: _activeBucket,
          breadcrumbs: _breadcrumbs,
          onOpenBucketList: () => unawaited(_loadBuckets()),
          onOpenBucketRoot: () => unawaited(_navToBucket(_activeBucketEntry!)),
          onOpenCrumb: (index) => unawaited(_navCrumb(index)),
        ),
        const SizedBox(height: 12),
        FileManagerActionBar(
          theme: theme,
          isGrid: _isGrid,
          searchController: _searchController,
          searchEnabled: !_loading,
          searchPlaceholder: _showTrash
              ? '搜索回收站名称或原路径'
              : _activeBucket == null
              ? '搜索存储桶'
              : '搜索文件或目录',
          selectedCount: _selectedObjectKeys.length,
          batchDownloadEnabled: _selectedObjects.any((object) => !object.isDir),
          showingTrash: _showTrash,
          onToggleView: () => setState(() => _isGrid = !_isGrid),
          trashCloseLabel: _isTrashHome ? '返回存储桶' : '返回文件',
          onOpenTrash:
              _isTrashHome ||
                  _activeBucket == null ||
                  _loading ||
                  _showTrash ||
                  !_activeBucketTrashEnabled
              ? null
              : _openBucketTrash,
          onCloseTrash: _activeBucket == null || _loading || !_showTrash
              ? null
              : _closeBucketTrash,
          onClearTrash:
              _activeBucket == null ||
                  _loading ||
                  !_showTrash ||
                  (_trashItems?.isEmpty ?? true)
              ? null
              : _clearBucketTrash,
          onCreateDirectory:
              _showTrash ||
                  _activeBucket == null ||
                  _loading ||
                  !_currentDirectoryWritable
              ? null
              : _createDirectory,
          onUpload:
              _showTrash ||
                  _activeBucket == null ||
                  _loading ||
                  !_currentDirectoryWritable
              ? null
              : _upload,
          onBatchDownload: _loading ? null : _downloadSelectedObjects,
          onBatchDelete: _loading || !_currentBucketWritable
              ? null
              : _deleteSelectedObjects,
          onClearSelection: _clearSelection,
        ),
      ],
    );
  }

  Widget _buildContent(ShadThemeData theme) {
    if (_loading) {
      return _buildLoadingView(theme);
    }
    if (_error != null) {
      return FileManagerErrorView(
        theme: theme,
        message: _error!,
        onRetry: _activeBucket == null
            ? () => unawaited(_loadBuckets())
            : () => unawaited(
                _loadObjects(_activeBucketEntry!, _prefix, forceRefresh: true),
              ),
        secondaryActionLabel: _activeBucket == null ? '重新配置认证信息' : null,
        onSecondaryAction: _activeBucket == null ? widget.onEditConfig : null,
      );
    }
    if (_activeBucket == null) return _buildBucketView(theme);
    if (_showTrash) return _buildTrashView(theme);
    return _buildObjectView(theme);
  }

  Widget _buildLoadingView(ShadThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLoadingIndicator(size: 22, strokeWidth: 2.4),
          const SizedBox(height: 12),
          Text(
            _loadingMessage,
            style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
          ),
          if (_loadingDetail != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                _loadingDetail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.mutedForeground,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildObjectView(ShadThemeData theme) {
    if (_objects == null) return const SizedBox();
    final visibleObjects = _filteredVisibleObjects;
    if (visibleObjects.isEmpty && _hasSearchQuery) {
      return FileManagerEmptyState(
        theme: theme,
        icon: LucideIcons.folderSearch,
        text: '当前搜索没有结果',
      );
    }
    return FileManagerObjectBrowser(
      objects: visibleObjects,
      prefix: _prefix,
      isGrid: _isGrid,
      scrollController: _contentScrollController,
      hasMore: _objectsHasMore,
      loadingMore: _pagingObjects,
      selectedKeys: _selectedObjectKeys,
      deletingKeys: _deletingObjectKeys,
      readOnly: _activeBucketReadOnly,
      supportsDirectoryDownload:
          widget.api.capabilities.supportsDownloadDirectory,
      gridIconSize: _gridIconSize,
      listIconSize: _listIconSize,
      mountedToDesktop: _activeMountStatus?.mounted ?? false,
      mountBucketName: _activeBucket,
      showSyncStatus: true,
      onOpenDirectory: (prefix) => unawaited(_navToPrefix(prefix)),
      onOpenFile: (object) => unawaited(_openObject(object)),
      onDownloadFile: (object) => unawaited(_downloadObject(object)),
      onNavigateUp: () => unawaited(_navUp()),
      onToggleSelection: _toggleObjectSelection,
      onSelectionSetChanged: _replaceSelectedObjects,
      onToggleSelectAll: _toggleSelectAllObjects,
      onCreateDirectory: _showTrash || _loading || !_currentDirectoryWritable
          ? null
          : () => unawaited(_createDirectory()),
      onUpload: _showTrash || _loading || !_currentDirectoryWritable
          ? null
          : () => unawaited(_upload()),
      onClearSelection: _clearSelection,
      onSelectionContextRequested: _selectObjectsForContextMenu,
      onSelectionAction: (action) =>
          unawaited(_handleSelectedObjectsAction(action)),
      supportsShareLinks: _activeConfig.supportsShareLinks,
      onObjectAction: (object, action) =>
          unawaited(_handleObjectAction(object, action)),
    );
  }
}
