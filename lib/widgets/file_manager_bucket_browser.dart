// Bucket browser keeps the bucket-only list/grid rendering out of the page file.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/whitesur_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';

part 'file_manager_bucket_source_actions.dart';
part 'file_manager_bucket_browser_actions.dart';
part 'file_manager_bucket_quota.dart';

const String _bucketContextMenuGroup = 'file_manager_bucket_browser';

class FileManagerBucketBrowser extends StatelessWidget {
  static const double _bucketActionColumnWidth = 244;
  static const double _bucketQuotaColumnWidth = 136;
  static const double _bucketSourceColumnWidth = 172;
  static const double _bucketActionHeaderInset = 14;

  const FileManagerBucketBrowser({
    super.key,
    required this.buckets,
    required this.isGrid,
    required this.gridIconSize,
    required this.listIconSize,
    required this.onOpenBucket,
    required this.mountStatuses,
    required this.busyBuckets,
    this.showActionColumn = true,
    this.actionColumnLabel = '操作',
    this.onOpenTrashBucket,
    this.onConfigureBucket,
    this.onMountBucket,
    this.onUnmountBucket,
    this.onOpenMountedBucket,
    this.onOpenWebDavBucket,
    this.bucketTrashEnabled,
    this.webDavActionLabel = 'WebDAV',
    this.onReorder,
  });

  final List<FileManagerBucketEntry> buckets;
  final bool isGrid;
  final double gridIconSize;
  final double listIconSize;
  final ValueChanged<FileManagerBucketEntry> onOpenBucket;
  final Map<String, BucketMountStatus> mountStatuses;
  final Set<String> busyBuckets;
  final bool showActionColumn;
  final String actionColumnLabel;
  final ValueChanged<FileManagerBucketEntry>? onOpenTrashBucket;
  final ValueChanged<FileManagerBucketEntry>? onConfigureBucket;
  final ValueChanged<FileManagerBucketEntry>? onMountBucket;
  final ValueChanged<FileManagerBucketEntry>? onUnmountBucket;
  final ValueChanged<FileManagerBucketEntry>? onOpenMountedBucket;
  final ValueChanged<FileManagerBucketEntry>? onOpenWebDavBucket;
  final bool Function(FileManagerBucketEntry bucket)? bucketTrashEnabled;
  final String webDavActionLabel;
  final void Function(int oldIndex, int newIndex)? onReorder;

  @override
  Widget build(BuildContext context) {
    if (isGrid) {
      return _buildGrid();
    }
    return _buildList(context);
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 118).floor().clamp(
          4,
          10,
        );
        return GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.92,
          children: buckets
              .map(
                (bucket) => _wrapGridBucketWithContextMenu(
                  bucket,
                  FileGridItem(
                    leading: WhiteSurFileIcon(
                      assetPath:
                          'assets/icons/whitesur/places/network-server-balanced.svg',
                      size: gridIconSize,
                    ),
                    title: bucket.label,
                    subtitle: '',
                    contentWidth: gridIconSize + 12,
                    onTap: () => _handleBucketTap(bucket),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  /// 桶列表列宽随容器收缩：优先保留操作，窄屏先收起独立来源列。
  (
    double quotaW,
    double sourceW,
    double actionW,
    bool showQuota,
    bool showSource,
    bool showActions,
  )
  _bucketListColumns(double maxWidth) {
    final showActions = showActionColumn;
    final showSource = maxWidth >= 720;
    final showQuota = maxWidth >= 420;
    final quotaW = showQuota ? _bucketQuotaColumnWidth : 0.0;
    final sourceW = showSource
        ? (maxWidth >= 920 ? _bucketSourceColumnWidth : 108.0)
        : 0.0;
    final actionW = showActions
        ? (maxWidth >= 1000 ? _bucketActionColumnWidth : 104.0)
        : 0.0;
    return (quotaW, sourceW, actionW, showQuota, showSource, showActions);
  }

  Widget _buildList(BuildContext context) {
    final headerTextStyle = const TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _bucketListColumns(constraints.maxWidth);
        final quotaW = cols.$1;
        final sourceW = cols.$2;
        final actionW = cols.$3;
        final showQuota = cols.$4;
        final showSource = cols.$5;
        final showActions = cols.$6;

        return ShadCard(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: ShadTheme.of(
                        context,
                      ).colorScheme.border.withValues(alpha: 0.75),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(width: listIconSize + 12),
                    const SizedBox(width: 12),
                    Expanded(child: Text('名称', style: headerTextStyle)),
                    if (showQuota) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: quotaW,
                        child: Text(
                          '已用 / 配额',
                          textAlign: TextAlign.right,
                          style: headerTextStyle,
                        ),
                      ),
                    ],
                    if (showSource) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: sourceW,
                        child: Text(
                          '来源',
                          textAlign: TextAlign.right,
                          style: headerTextStyle,
                        ),
                      ),
                    ],
                    if (showActions) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: actionW,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: _bucketActionHeaderInset,
                          ),
                          child: Text(
                            actionColumnLabel,
                            textAlign: TextAlign.left,
                            style: headerTextStyle,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _buildBucketRows(
                  showSource: showSource,
                  showActions: showActions,
                  showQuota: showQuota,
                  quotaW: quotaW,
                  sourceW: sourceW,
                  actionW: actionW,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBucketRows({
    required bool showSource,
    required bool showActions,
    required bool showQuota,
    required double quotaW,
    required double sourceW,
    required double actionW,
  }) {
    final canReorder = onReorder != null && buckets.length > 1;
    if (canReorder) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: buckets.length,
        // Classic onReorder API keeps this building on Flutter 3.41;
        // onReorderItem exists only on 3.47+.
        onReorder: onReorder!,
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 1.5,
            color: Colors.transparent,
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final bucket = buckets[index];
          return ReorderableDragStartListener(
            key: ValueKey('bucket-${bucket.id}'),
            index: index,
            child: _buildBucketListRow(
              context: context,
              bucket: bucket,
              index: index,
              showSource: showSource,
              showActions: showActions,
              showQuota: showQuota,
              quotaW: quotaW,
              sourceW: sourceW,
              actionW: actionW,
              showDragHandle: true,
            ),
          );
        },
      );
    }
    return ListView.builder(
      itemCount: buckets.length,
      itemBuilder: (context, index) {
        final bucket = buckets[index];
        return KeyedSubtree(
          key: ValueKey('bucket-${bucket.id}'),
          child: _buildBucketListRow(
            context: context,
            bucket: bucket,
            index: index,
            showSource: showSource,
            showActions: showActions,
            showQuota: showQuota,
            quotaW: quotaW,
            sourceW: sourceW,
            actionW: actionW,
            showDragHandle: false,
          ),
        );
      },
    );
  }

  Widget _buildBucketListRow({
    required BuildContext context,
    required FileManagerBucketEntry bucket,
    required int index,
    required bool showSource,
    required bool showActions,
    required bool showQuota,
    required double quotaW,
    required double sourceW,
    required double actionW,
    required bool showDragHandle,
  }) {
    final theme = ShadTheme.of(context);
    final trailing = (showSource || showActions)
        ? _BucketSourceAndActions(
            sourceLabel: bucket.sourceLabel,
            showSourceColumn: showSource,
            showActionColumn: showActions,
            actionColumnWidth: actionW,
            sourceColumnWidth: sourceW,
            child: _BucketMountActions(
              bucket: bucket,
              status: mountStatuses[bucket.id],
              busy: busyBuckets.contains(bucket.id),
              onMountBucket: onMountBucket,
              onUnmountBucket: onUnmountBucket,
              onOpenMountedBucket: onOpenMountedBucket,
              onConfigureBucket: onConfigureBucket,
              moreMenuItems: _buildBucketMenuItems(bucket),
            ),
          )
        : const SizedBox.shrink();
    return _wrapBucketWithContextMenu(
      bucket,
      FileListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDragHandle) ...[
              Icon(
                LucideIcons.gripVertical,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 6),
            ],
            WhiteSurFileIcon(
              assetPath:
                  'assets/icons/whitesur/places/network-server-balanced.svg',
              size: listIconSize,
            ),
          ],
        ),
        title: bucket.label,
        subtitleLabel: showSource ? '' : bucket.sourceLabel,
        sizeWidget: showQuota ? _bucketQuotaUsage(context, bucket) : null,
        sizeColumnWidthOverride: quotaW,
        onTap: () => _handleBucketTap(bucket),
        showDivider: index != buckets.length - 1,
        trailing: trailing,
      ),
    );
  }

  Widget _wrapGridBucketWithContextMenu(
    FileManagerBucketEntry bucket,
    Widget child,
  ) {
    return _wrapBucketWithContextMenu(bucket, child);
  }

  Widget _wrapBucketWithContextMenu(
    FileManagerBucketEntry bucket,
    Widget child,
  ) {
    final items = _buildBucketMenuItems(bucket);
    if (items.isEmpty) {
      return child;
    }
    return DesktopContextMenuRegion(
      groupId: _bucketContextMenuGroup,
      items: items,
      child: child,
    );
  }

  List<Widget> _buildBucketMenuItems(FileManagerBucketEntry bucket) {
    final status = mountStatuses[bucket.id];
    final busy = busyBuckets.contains(bucket.id);
    final mounted = status?.mounted ?? false;
    final showsWebDavAction = onOpenWebDavBucket != null;
    final trashEnabled =
        bucketTrashEnabled?.call(bucket) ?? onOpenTrashBucket != null;

    return <Widget>[
      ShadContextMenuItem(
        onPressed: () => _runBucketMenuAction(() => onOpenBucket(bucket)),
        child: const Text('打开存储桶'),
      ),
      if (onConfigureBucket != null)
        ShadContextMenuItem(
          onPressed: () =>
              _runBucketMenuAction(() => onConfigureBucket!(bucket)),
          child: const Text('桶设置'),
        ),
      if (showsWebDavAction && !busy) ...[
        if (onOpenTrashBucket != null && trashEnabled)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onOpenTrashBucket!(bucket)),
            child: const Text('打开回收站'),
          ),
        ShadContextMenuItem(
          onPressed: () =>
              _runBucketMenuAction(() => onOpenWebDavBucket!(bucket)),
          child: Text('查看 $webDavActionLabel 地址'),
        ),
      ] else if (mounted && !busy) ...[
        if (onOpenTrashBucket != null && trashEnabled)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onOpenTrashBucket!(bucket)),
            child: const Text('打开回收站'),
          ),
        if (onOpenMountedBucket != null)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onOpenMountedBucket!(bucket)),
            child: const Text('打开挂载目录'),
          ),
        if (onUnmountBucket != null)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onUnmountBucket!(bucket)),
            child: const Text('卸载'),
          ),
      ] else ...[
        if (onOpenTrashBucket != null && trashEnabled)
          ShadContextMenuItem(
            onPressed: () =>
                _runBucketMenuAction(() => onOpenTrashBucket!(bucket)),
            child: const Text('打开回收站'),
          ),
        if (!busy && onMountBucket != null)
          ShadContextMenuItem(
            onPressed: () => _runBucketMenuAction(() => onMountBucket!(bucket)),
            child: const Text('挂载'),
          ),
      ],
    ];
  }

  void _handleBucketTap(FileManagerBucketEntry bucket) {
    if (_dismissActiveContextMenu()) {
      return;
    }
    onOpenBucket(bucket);
  }

  bool _dismissActiveContextMenu() {
    return DesktopContextMenuRegistry.dismiss(_bucketContextMenuGroup);
  }

  void _runBucketMenuAction(VoidCallback action) {
    DesktopContextMenuRegistry.dismiss(_bucketContextMenuGroup);
    action();
  }
}
