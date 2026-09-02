// 文件对象区：负责列表/网格渲染、非根目录的 ".." 返回项，以及对象交互分发。
//
// cursor 约定：本浏览器及外层绝不在文件行/网格项之外再包一层设
// SystemMouseCursors.click 的 MouseRegion。行级 cursor 由 FileListTile /
// FileGridItem 自身拥有（见 file_list_tile.dart 的 cursor 注释）。一旦外层也
// 设 click，hover 离开行后整个浏览器区域都会停在手指状态。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_manager_drag_selection.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:remote_storage/widgets/file_manager_object_header.dart';
import 'package:remote_storage/widgets/file_sync_status_badge.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/widgets/app_loading_indicator.dart';

part 'file_manager_object_browser_menus.dart';
part 'file_manager_object_browser_helpers.dart';
part 'file_manager_object_browser_mobile.dart';
part 'file_manager_object_browser_sync.dart';

const String _objectContextMenuGroup = 'file_manager_object_browser';
final DesktopContextMenuHandle _backgroundContextMenuHandle =
    DesktopContextMenuHandle();

class FileManagerObjectBrowser extends StatelessWidget {
  static const double _gridChildAspectRatio = 0.9;

  const FileManagerObjectBrowser({
    super.key,
    required this.objects,
    required this.prefix,
    required this.isGrid,
    required this.scrollController,
    required this.hasMore,
    required this.loadingMore,
    required this.selectedKeys,
    required this.deletingKeys,
    this.readOnly = false,
    this.supportsDirectoryDownload = true,
    this.supportsBrowserTransfers = false,
    required this.gridIconSize,
    required this.listIconSize,
    this.mountedToDesktop = false,
    this.mountBucketName,
    this.profileId,
    this.showSyncStatus = false,
    this.mobilePresentation = false,
    required this.onOpenDirectory,
    required this.onOpenFile,
    required this.onDownloadFile,
    required this.onNavigateUp,
    required this.onToggleSelection,
    required this.onSelectionSetChanged,
    required this.onToggleSelectAll,
    this.onCreateDirectory,
    this.onUpload,
    this.onClearSelection,
    this.onSelectionContextRequested,
    this.onSelectionAction,
    this.supportsShareLinks = true,
    required this.onObjectAction,
  });

  static const ObjectInfo _parentDirectoryEntry = ObjectInfo(
    key: '../',
    size: 0,
    lastModified: '',
    isDir: true,
  );

  final List<ObjectInfo> objects;
  final String prefix;
  final bool isGrid;
  final ScrollController scrollController;
  final bool hasMore;
  final bool loadingMore;
  final Set<String> selectedKeys;
  final Set<String> deletingKeys;
  final bool readOnly;
  final bool supportsDirectoryDownload;

  /// Browser downloads intentionally skip directories; desktop/mobile native
  /// transfers may use the recursive directory lister when supported.
  final bool supportsBrowserTransfers;
  final double gridIconSize;
  final double listIconSize;
  final String? mountBucketName;
  final String? profileId;
  final bool mountedToDesktop;
  final bool showSyncStatus;

  /// Android uses a compact row-only surface; desktop keeps the table/grid.
  final bool mobilePresentation;
  final ValueChanged<String> onOpenDirectory;
  final ValueChanged<ObjectInfo> onOpenFile;
  final ValueChanged<ObjectInfo> onDownloadFile;
  final VoidCallback onNavigateUp;
  final ValueChanged<ObjectInfo> onToggleSelection;
  final ValueChanged<Set<String>> onSelectionSetChanged;
  final VoidCallback onToggleSelectAll;
  final VoidCallback? onCreateDirectory;
  final VoidCallback? onUpload;
  final VoidCallback? onClearSelection;
  final ValueChanged<ObjectInfo>? onSelectionContextRequested;
  final ValueChanged<FileSelectionAction>? onSelectionAction;
  final bool supportsShareLinks;
  final void Function(ObjectInfo object, FileObjectAction action)
  onObjectAction;

  @override
  Widget build(BuildContext context) {
    if (showSyncStatus) {
      return AnimatedBuilder(
        animation: RemoteTaskStore.instance,
        builder: (context, _) =>
            _buildBody(context, RemoteTaskStore.instance.tasks),
      );
    }
    return _buildBody(context, null);
  }

  Widget _buildBody(BuildContext context, List<RemoteTask>? tasks) {
    final theme = ShadTheme.of(context);
    final visibleObjects = prefix.isEmpty
        ? objects
        : [_parentDirectoryEntry, ...objects];
    final body = visibleObjects.isEmpty
        ? _buildEmptyState(theme)
        : mobilePresentation
        ? _buildMobileList(context, visibleObjects, theme, tasks)
        : isGrid
        ? _buildGrid(visibleObjects, theme, tasks)
        : _buildList(visibleObjects, theme, tasks);
    final selectionBody = FileManagerDragSelection(
      enabled: true,
      selectedKeys: selectedKeys,
      onSelectionChanged: onSelectionSetChanged,
      onBlankTap: onClearSelection,
      onBlankSecondaryTapDown: _showBackgroundContextMenu,
      child: body,
    );
    // Right-click/blank-area menus are desktop affordances. Mobile rows own
    // their long-press and overflow-sheet gestures instead.
    if (mobilePresentation) return selectionBody;
    return DesktopContextMenuRegion(
      groupId: _objectContextMenuGroup,
      items: _buildBackgroundMenuItems(),
      handle: _backgroundContextMenuHandle,
      captureSecondaryTap: false,
      child: selectionBody,
    );
  }

  Widget _buildEmptyState(ShadThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.folderOpen,
            size: 44,
            color: theme.colorScheme.mutedForeground.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 14),
          Text(
            '此目录为空',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    List<ObjectInfo> objects,
    ShadThemeData theme,
    List<RemoteTask>? tasks,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isAndroid = Theme.of(context).platform == TargetPlatform.android;
        final crossAxisCount = isAndroid
            ? (constraints.maxWidth / 150).floor().clamp(2, 4)
            : (constraints.maxWidth / 118).floor().clamp(4, 10);
        return GridView.count(
          controller: scrollController,
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: _gridChildAspectRatio,
          children: [
            ...objects.map(
              (object) => _selectionTarget(
                object,
                _wrapWithContextMenu(
                  object,
                  FileGridItem(
                    leading: _leading(object, theme, gridIconSize),
                    title: _title(object),
                    subtitle: _subtitle(object, forGrid: true),
                    bottomOverlay: mountedToDesktop
                        ? _syncBadge(object, tasks)
                        : null,
                    onTap: _tapHandler(object),
                    onDoubleTap: null,
                    onTitleTap: _titleTapHandler(object),
                    onSelectionTap: _selectionTapHandler(object),
                    isSelected: _isSelected(object),
                    showSelectionControl: _showsSelectionControl(object),
                    deleting: _isDeleting(object),
                  ),
                ),
              ),
            ),
            if (loadingMore) _buildGridLoadingTile(theme),
          ],
        );
      },
    );
  }

  Widget _buildGridLoadingTile(ShadThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.5),
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: AppLoadingIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }

  Widget _buildList(
    List<ObjectInfo> objects,
    ShadThemeData theme,
    List<RemoteTask>? tasks,
  ) {
    final selectableObjects = objects.where(
      (object) => !_isParentDirectory(object),
    );
    final selectedCount = selectableObjects
        .where((object) => selectedKeys.contains(object.key))
        .length;
    final totalCount = selectableObjects.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return ShadCard(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              FileManagerObjectHeader(
                theme: theme,
                showSelectionControl: true,
                allSelected: totalCount > 0 && selectedCount == totalCount,
                partiallySelected:
                    selectedCount > 0 && selectedCount < totalCount,
                onToggleSelectAll: onToggleSelectAll,
                showSyncStatus: showSyncStatus,
                compact: compact,
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: objects.length + (loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= objects.length) {
                      return _buildListLoadingRow(theme);
                    }
                    final object = objects[index];
                    return _buildListObjectRow(
                      context,
                      object,
                      theme,
                      tasks,
                      index,
                      compact,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListLoadingRow(ShadThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: AppLoadingIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
