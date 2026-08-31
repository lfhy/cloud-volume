// 文件管理页：负责面包屑导航、桶/对象浏览，以及上传下载交互。
import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/sync_remote_open_request.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/file_access_service.dart';
import 'package:remote_storage/services/file_access_transfer_request.dart';
import 'package:remote_storage/services/desktop_file_transfer_service.dart';
import 'package:remote_storage/services/clipboard_shortcut_channel.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/bucket_settings_dialog.dart';
import 'package:remote_storage/state/object_listing_notifier.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/state/share_records_notifier.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:remote_storage/utils/app_log.dart';
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
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/bucket_source_service.dart';
part 'file_manager_page_actions.dart';
part 'file_manager_page_action_feedback.dart';
part 'file_manager_page_access.dart';
part 'file_manager_page_bucket_policy.dart';
part 'file_manager_page_bucket_loading.dart';
part 'file_manager_page_bucket_view.dart';
part 'file_manager_page_downloads.dart';
part 'file_manager_page_mount.dart';
part 'file_manager_page_mobile_rebind.dart';
part 'file_manager_page_object_loading.dart';
part 'file_manager_page_object_view.dart';
part 'file_manager_page_object_deletes.dart';
part 'file_manager_page_paging.dart';
part 'file_manager_page_preview.dart';
part 'file_manager_page_quota.dart';
part 'file_manager_page_restore_sync.dart';
part 'file_manager_page_selected_actions.dart';
part 'file_manager_page_state.dart';
part 'file_manager_page_selection.dart';
part 'file_manager_page_sources.dart';
part 'file_manager_page_transfer_inputs.dart';
part 'file_manager_page_trash.dart';
part 'file_manager_page_upload_feedback.dart';
part 'file_manager_page_uploads.dart';
part 'file_manager_page_sync_nav.dart';
part 'file_manager_page_webdav.dart';
part 'file_manager_workspace.dart';

// 文件管理页首页模式：既支持普通文件浏览，也支持侧边栏独立回收站入口。
enum FileManagerHomeView { files, trash }

/// Desktop entry point for the desktop file-manager presentation.
class FileManagerPage extends StatelessWidget {
  const FileManagerPage({
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
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final List<ProfileInfo> profiles;
  final VoidCallback onRefresh;
  final FileManagerHomeView homeView;
  final SyncRemoteOpenRequest? pendingSyncRemoteOpen;
  final int pendingSyncRemoteOpenGeneration;
  final SyncRemoteOpenConsumer? onPendingSyncRemoteOpenConsumed;

  /// Jumps to the account-management page when a source needs repair.
  final VoidCallback? onOpenAccountManagement;

  @override
  Widget build(BuildContext context) {
    return FileManagerWorkspace(
      api: api,
      config: config,
      profiles: profiles,
      onRefresh: onRefresh,
      homeView: homeView,
      pendingSyncRemoteOpen: pendingSyncRemoteOpen,
      pendingSyncRemoteOpenGeneration: pendingSyncRemoteOpenGeneration,
      onPendingSyncRemoteOpenConsumed: onPendingSyncRemoteOpenConsumed,
      onOpenAccountManagement: onOpenAccountManagement,
    );
  }
}

class _FileManagerPageState extends State<FileManagerWorkspace> {
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
  final Map<String, _BucketQuotaCacheValue> _bucketQuotaCache =
      <String, _BucketQuotaCacheValue>{};
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
  // Android keeps its own file-location history so an in-flight bucket or
  // recycle-bin request still consumes Back before the shell changes tabs.
  final List<_MobileFileManagerLocation> _mobileLocationHistory =
      <_MobileFileManagerLocation>[];
  _MobileFileManagerLocation _mobileLocation =
      const _MobileFileManagerLocation.bucketList();
  int _mobileNavigationEpoch = 0;
  // Input generation is separate from navigation: A → B → A stays valid,
  // while a bootstrap/profile replacement invalidates every old source entry.
  int _mobileInputGeneration = 0;
  Future<void>? _mobileInputRebind;
  bool _mobileInputRefreshNeedsRebind = false;
  final Map<int, int> _mobileInputGenerationByListingView = <int, int>{};
  int _pendingSyncRemoteOpenGeneration = 0;
  int? _activeDesktopSyncRemoteOpenGeneration;
  _FileManagerLoadingSnapshot? _desktopSyncLoadingSnapshot;
  _DesktopListingResumeTarget? _desktopListingResumeTarget;
  SyncRemoteOpenRequest? _activeMobileSyncRemoteOpen;
  int? _activeMobileSyncRemoteOpenTicket;
  _MobileFileManagerLocation? _mobileSyncRemoteOpenOrigin;
  int? _mobileSyncRemoteOpenHistoryBase;
  int _seenObjectListingMutationVersion = 0,
      _bucketQuotaRefreshGeneration = 0,
      _listingViewGeneration = 0,
      _objectListingCacheGeneration = 0;
  List<BucketSourceLoadFailure> _unavailableBucketSources =
      const <BucketSourceLoadFailure>[];
  final Map<String, _PendingUploadRefresh> _pendingUploadRefreshes =
      <String, _PendingUploadRefresh>{};
  final Map<String, _PendingMetadataTaskRefresh> _pendingMetadataTaskRefreshes =
      <String, _PendingMetadataTaskRefresh>{};
  final Map<String, RemoteTaskStatus> _seenMetadataTaskStates =
      <String, RemoteTaskStatus>{};
  bool _metadataTaskRefreshInFlight = false;

  // Keep setState inside the State subclass; view extensions only coordinate UI.
  void _replaceBucketsAfterReorder(List<FileManagerBucketEntry> buckets) {
    setState(() => _buckets = buckets);
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
    _contentScrollController.addListener(_maybeLoadMoreContent);
    ObjectListingNotifier.instance.addListener(_handleObjectListingMutation);
    RemoteTaskStore.instance.addListener(_handleUploadTaskRefresh);
    _startMountStatusRefreshTimer();
    _loadBuckets();
    if (ClipboardShortcutChannel.instance.isSupported) {
      ClipboardShortcutChannel.instance.start(
        onPaste: _handleNativePaste,
        onCopy: _handleNativeCopy,
      );
    }
    final pending = widget.pendingSyncRemoteOpen;
    if (pending != null) {
      schedulePendingSyncRemoteOpen(
        pending,
        widget.pendingSyncRemoteOpenGeneration,
      );
    }
  }

  @override
  void dispose() {
    _loadingDetailTimer?.cancel();
    _mountStatusRefreshTimer?.cancel();
    ObjectListingNotifier.instance.removeListener(_handleObjectListingMutation);
    RemoteTaskStore.instance.removeListener(_handleUploadTaskRefresh);
    _contentScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FileManagerWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config ||
        oldWidget.profiles != widget.profiles) {
      if (widget.viewBuilder == null) {
        _mobileLocationHistory.clear();
        _mobileLocation = const _MobileFileManagerLocation.bucketList();
        _mobileNavigationEpoch++;
        unawaited(_loadBuckets());
      } else {
        // Soft bootstrap refreshes replace config/profile instances even when
        // the open Android file location is still valid.
        _scheduleMobileFileManagerInputRebind();
      }
    }
    final pending = widget.pendingSyncRemoteOpen;
    if (pending == null) {
      if (widget.viewBuilder == null) {
        _cancelPendingDesktopSyncRemoteOpen();
      } else {
        _cancelPendingMobileSyncRemoteOpen(notifyParent: false);
      }
    } else if (pending != oldWidget.pendingSyncRemoteOpen ||
        widget.pendingSyncRemoteOpenGeneration !=
            oldWidget.pendingSyncRemoteOpenGeneration) {
      schedulePendingSyncRemoteOpen(
        pending,
        widget.pendingSyncRemoteOpenGeneration,
      );
    }
  }

  void _startMountStatusRefreshTimer() {
    _mountStatusRefreshTimer?.cancel();
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
      _pagingObjects = false;
      _pagingTrash = false;
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
    final viewBuilder = widget.viewBuilder;
    if (viewBuilder != null) {
      return viewBuilder(context, FileManagerWorkspaceController._(this));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 32, right: 32, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          const SizedBox(height: 16),
          Expanded(child: _buildFileTransferSurface(theme)),
        ],
      ),
    );
  }

  // Native desktop drop APIs are only mounted around the desktop presentation.
  Widget _buildFileTransferSurface(ShadThemeData theme) {
    final content = _buildContentWithMountLoading(theme);
    if (!isDesktopPlatform && !isWebPlatform) {
      return content;
    }
    return FileTransferClipboardRegion(
      enabled: _acceptsFileTransferInput,
      acceptsLocalFiles: _currentDirectoryWritable,
      onPasteLocalFiles: (paths) => unawaited(_uploadLocalPaths(paths)),
      onCopySelection: () => unawaited(_copySelectedObjectsToClipboard()),
      child: content,
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
          activeBucket: _activeBucketLabel,
          breadcrumbs: _breadcrumbs,
          onOpenBucketList: () => unawaited(_loadBuckets(force: true)),
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
              : () => _openBucketTrash(),
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
            ? () => unawaited(_loadBuckets(force: true))
            : () => unawaited(
                _loadObjects(_activeBucketEntry!, _prefix, forceRefresh: true),
              ),
        secondaryActionLabel: _activeBucket == null ? '账号管理' : null,
        onSecondaryAction: _activeBucket == null
            ? () => widget.onOpenAccountManagement?.call()
            : null,
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
}
