// Android files page: owns the touch-first presentation while the shared
// workspace supplies only loading state and file operations.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/sync_remote_open_request.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/mobile_file_manager_navigation.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/file_manager_error_view.dart';
import 'package:remote_storage/widgets/mobile_file_manager_browser.dart';
import 'package:remote_storage/widgets/mobile_file_manager_surface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'mobile_file_manager_actions.dart';

/// Dedicated Android page entry point. It has its own layout, list renderer,
/// action sheet, and Back lifecycle; only data and mutations come from the
/// platform-neutral [FileManagerWorkspace].
class MobileFileManagerPage extends StatefulWidget {
  const MobileFileManagerPage({
    super.key,
    required this.api,
    required this.config,
    required this.profiles,
    required this.onRefresh,
    this.homeView = FileManagerHomeView.files,
    this.pendingSyncRemoteOpen,
    this.pendingSyncRemoteOpenGeneration = 0,
    this.onPendingSyncRemoteOpenConsumed,
    this.onCancelPendingSyncRemoteOpen,
    this.onOpenAccountManagement,
    this.onOpenSettings,
    this.navigation,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final List<ProfileInfo> profiles;
  final VoidCallback onRefresh;
  final FileManagerHomeView homeView;
  final SyncRemoteOpenRequest? pendingSyncRemoteOpen;
  final int pendingSyncRemoteOpenGeneration;
  final SyncRemoteOpenConsumer? onPendingSyncRemoteOpenConsumed;
  final VoidCallback? onCancelPendingSyncRemoteOpen;
  final VoidCallback? onOpenAccountManagement;
  final VoidCallback? onOpenSettings;
  final MobileFileManagerNavigation? navigation;

  @override
  State<MobileFileManagerPage> createState() => _MobileFileManagerPageState();
}

class _MobileFileManagerPageState extends State<MobileFileManagerPage> {
  FileManagerWorkspaceController? _workspace;

  @override
  void initState() {
    super.initState();
    widget.navigation?.bind(_handleSystemBack);
  }

  @override
  void didUpdateWidget(covariant MobileFileManagerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigation == widget.navigation) return;
    oldWidget.navigation?.clear();
    widget.navigation?.bind(_handleSystemBack);
  }

  @override
  void dispose() {
    widget.navigation?.clear();
    super.dispose();
  }

  Future<bool> _handleSystemBack() async =>
      await _workspace?.handleSystemBack() ?? false;

  @override
  Widget build(BuildContext context) {
    return FileManagerWorkspace(
      api: widget.api,
      config: widget.config,
      profiles: widget.profiles,
      onRefresh: widget.onRefresh,
      homeView: widget.homeView,
      pendingSyncRemoteOpen: widget.pendingSyncRemoteOpen,
      pendingSyncRemoteOpenGeneration: widget.pendingSyncRemoteOpenGeneration,
      onPendingSyncRemoteOpenConsumed: widget.onPendingSyncRemoteOpenConsumed,
      onOpenAccountManagement: widget.onOpenAccountManagement,
      viewBuilder: _buildWorkspace,
    );
  }

  Widget _buildWorkspace(
    BuildContext context,
    FileManagerWorkspaceController workspace,
  ) {
    _workspace = workspace;
    final theme = ShadTheme.of(context);
    return MobileFileManagerSurface(
      title: _titleFor(workspace),
      subtitle: _subtitleFor(workspace),
      searchController: workspace.searchController,
      searchEnabled: !workspace.isLoading,
      searchPlaceholder: _searchPlaceholderFor(workspace),
      body: _buildContent(context, workspace, theme),
      onBack: workspace.canNavigateBack ? () => _handleBack(workspace) : null,
      onSettings: widget.onOpenSettings,
      // A previous bucket entry may carry a stale profile while inputs are
      // rebinding, so no action sheet is exposed until the fresh list lands.
      onMore: workspace.isLoading || workspace.isInputRebindPending
          ? null
          : () => unawaited(showMobileFileManagerActions(context, workspace)),
      onFab: () => unawaited(
        showMobileFileManagerActions(context, workspace, fromFab: true),
      ),
      showFab:
          workspace.hasActiveBucket &&
          !workspace.isShowingTrash &&
          workspace.error == null &&
          workspace.currentDirectoryWritable &&
          !workspace.isLoading &&
          !workspace.isInputRebindPending,
    );
  }

  String _titleFor(FileManagerWorkspaceController workspace) {
    final active = workspace.activeBucketEntry;
    if (active == null) return workspace.isTrashHome ? '回收站' : '文件';
    if (workspace.isShowingTrash) return active.label;
    if (workspace.breadcrumbs.isEmpty) return active.label;
    return workspace.breadcrumbs.last;
  }

  void _handleBack(FileManagerWorkspaceController workspace) {
    if (workspace.hasPendingSyncRemoteOpen &&
        widget.onCancelPendingSyncRemoteOpen != null) {
      widget.onCancelPendingSyncRemoteOpen!();
      return;
    }
    unawaited(workspace.handleSystemBack());
  }

  String _subtitleFor(FileManagerWorkspaceController workspace) {
    final active = workspace.activeBucketEntry;
    if (active == null) {
      return workspace.isTrashHome ? '选择存储桶' : '所有存储桶';
    }
    if (workspace.isShowingTrash) return '回收站 · ${active.label}';
    if (workspace.isAtBucketRoot) return active.sourceLabel;
    return '${active.label} / ${workspace.breadcrumbs.join(' / ')}';
  }

  String _searchPlaceholderFor(FileManagerWorkspaceController workspace) {
    if (workspace.isShowingTrash) return '搜索回收站名称或原路径';
    return workspace.hasActiveBucket ? '搜索文件或目录' : '搜索存储桶';
  }

  List<ObjectInfo> _objectsFor(FileManagerWorkspaceController workspace) {
    if (workspace.isAtBucketRoot) return workspace.visibleObjects;
    return <ObjectInfo>[
      const ObjectInfo(key: '../', size: 0, lastModified: '', isDir: true),
      ...workspace.visibleObjects,
    ];
  }

  Widget _buildContent(
    BuildContext context,
    FileManagerWorkspaceController workspace,
    ShadThemeData theme,
  ) {
    if (workspace.isLoading) return _buildLoading(workspace, theme);
    if (workspace.error case final error?) {
      return FileManagerErrorView(
        theme: theme,
        message: error,
        onRetry: () => unawaited(workspace.refresh()),
        secondaryActionLabel:
            !workspace.hasActiveBucket && workspace.canOpenAccountManagement
            ? '账号管理'
            : null,
        onSecondaryAction:
            !workspace.hasActiveBucket && workspace.canOpenAccountManagement
            ? workspace.openAccountManagement
            : null,
      );
    }
    if (!workspace.hasActiveBucket) {
      final browser = MobileFileManagerBrowser(
        section: MobileFileManagerSection.buckets,
        scrollController: workspace.contentScrollController,
        buckets: workspace.buckets,
        onOpenBucket: (bucket) => unawaited(workspace.openBucket(bucket)),
        onBucketMenu: (bucket) =>
            unawaited(showMobileBucketActions(context, workspace, bucket)),
        emptyText: workspace.hasSearchQuery ? '没有匹配的存储桶' : '没有可用的存储桶',
      );
      if (workspace.unavailableSourceCount == 0) return browser;
      return Column(
        children: [
          _MobileUnavailableSourceWarning(
            count: workspace.unavailableSourceCount,
            onRepair: workspace.openAccountManagement,
          ),
          Expanded(child: browser),
        ],
      );
    }
    if (workspace.isShowingTrash) {
      return MobileFileManagerBrowser(
        section: MobileFileManagerSection.trash,
        scrollController: workspace.contentScrollController,
        trashItems: workspace.trashItems,
        hasMore: workspace.trashHasMore,
        loadingMore: workspace.pagingTrash,
        onTrashMenu: (item) =>
            unawaited(showMobileTrashActions(context, workspace, item)),
        emptyText: workspace.hasSearchQuery ? '当前搜索没有结果' : '此存储桶回收站为空',
      );
    }
    return MobileFileManagerBrowser(
      section: MobileFileManagerSection.objects,
      scrollController: workspace.contentScrollController,
      objects: _objectsFor(workspace),
      hasMore: workspace.objectsHasMore,
      loadingMore: workspace.pagingObjects,
      selectedKeys: workspace.selectedObjectKeys,
      onOpenDirectory: (prefix) => unawaited(workspace.openDirectory(prefix)),
      onOpenFile: (object) => unawaited(workspace.openFile(object)),
      onNavigateUp: () => unawaited(workspace.navigateBack()),
      onObjectMenu: (object) =>
          unawaited(showMobileObjectActions(context, workspace, object)),
      onToggleSelection: workspace.toggleSelection,
      emptyText: workspace.hasSearchQuery ? '当前搜索没有结果' : '此目录为空',
    );
  }

  Widget _buildLoading(
    FileManagerWorkspaceController workspace,
    ShadThemeData theme,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLoadingIndicator(size: 22, strokeWidth: 2.4),
          const SizedBox(height: 12),
          Text(
            workspace.loadingMessage,
            style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
          ),
          if (workspace.loadingDetail case final detail?) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                detail,
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

class _MobileUnavailableSourceWarning extends StatelessWidget {
  const _MobileUnavailableSourceWarning({
    required this.count,
    required this.onRepair,
  });

  final int count;
  final VoidCallback onRepair;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 18,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count 个账号暂时无法访问',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: onRepair,
            child: const Text('重新配置'),
          ),
        ],
      ),
    );
  }
}
