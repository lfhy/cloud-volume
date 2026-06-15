// 全局回收站浏览区：复用标准文件列表样式展示跨桶的已删除项目。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:remote_storage/widgets/trash_row_actions.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/widgets/app_loading_indicator.dart';

const String _globalTrashContextMenuGroup = 'global_trash_browser';

class GlobalTrashBrowserEntry {
  const GlobalTrashBrowserEntry({required this.bucket, required this.item});

  final String bucket;
  final TrashItem item;

  String get id => '$bucket:${item.id}';

  DateTime? get deletedAtDateTime =>
      DateTime.tryParse(item.deletedAt)?.toLocal();
}

class GlobalTrashBrowser extends StatelessWidget {
  static const double _bucketColumnWidth = 154;

  const GlobalTrashBrowser({
    super.key,
    required this.entries,
    required this.scrollController,
    required this.loadingMore,
    required this.selectedIds,
    required this.busyIds,
    this.showBucketColumn = true,
    required this.onToggleSelection,
    required this.onToggleSelectAll,
    required this.onRestore,
    required this.onDeletePermanently,
  });

  final List<GlobalTrashBrowserEntry> entries;
  final ScrollController scrollController;
  final bool loadingMore;
  final Set<String> selectedIds;
  final Set<String> busyIds;
  final bool showBucketColumn;
  final ValueChanged<GlobalTrashBrowserEntry> onToggleSelection;
  final VoidCallback onToggleSelectAll;
  final ValueChanged<GlobalTrashBrowserEntry> onRestore;
  final ValueChanged<GlobalTrashBrowserEntry> onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final selectableEntries = entries
        .where((entry) => !busyIds.contains(entry.id))
        .toList(growable: false);
    final selectedCount = selectableEntries
        .where((entry) => selectedIds.contains(entry.id))
        .length;
    final allSelected =
        selectableEntries.isNotEmpty &&
        selectedCount == selectableEntries.length;
    final partiallySelected =
        selectedCount > 0 && selectedCount < selectableEntries.length;

    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _GlobalTrashHeader(
            theme: theme,
            showBucketColumn: showBucketColumn,
            allSelected: allSelected,
            partiallySelected: partiallySelected,
            onToggleSelectAll: onToggleSelectAll,
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: entries.length + (loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= entries.length) {
                  return _buildLoadingRow(theme);
                }
                final entry = entries[index];
                final busy = busyIds.contains(entry.id);
                return _wrapWithContextMenu(
                  entry,
                  FileListTile(
                    leading: LocalCloudPanFileIcon(
                      name: entry.item.name,
                      isDirectory: entry.item.isDir,
                      size: 32,
                    ),
                    title: entry.item.name,
                    subtitleLabel: entry.item.originalKey,
                    sizeLabel: showBucketColumn ? entry.bucket : '',
                    sizeColumnWidthOverride: showBucketColumn
                        ? _bucketColumnWidth
                        : 0,
                    modifiedLabel: busy ? '处理中...' : entry.item.deletedAt,
                    onTap: () => _toggleEntry(entry),
                    onDoubleTap: busy ? null : () => onRestore(entry),
                    onTitleTap: () => _toggleEntry(entry),
                    onSelectionTap: busy
                        ? null
                        : () => onToggleSelection(entry),
                    isSelected: selectedIds.contains(entry.id),
                    showSelectionControl: true,
                    showDivider: index != entries.length - 1 || loadingMore,
                    deleting: busy,
                    trailing: TrashRowActions(
                      deletedLabel: entry.item.deletedAt,
                      busy: busy,
                      onRestore: () => onRestore(entry),
                      onDeletePermanently: () => onDeletePermanently(entry),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapWithContextMenu(GlobalTrashBrowserEntry entry, Widget child) {
    return DesktopContextMenuRegion(
      groupId: _globalTrashContextMenuGroup,
      items: [
        ShadContextMenuItem(
          onPressed: () => _runMenuAction(() => onRestore(entry)),
          child: const Text('恢复'),
        ),
        ShadContextMenuItem(
          onPressed: () => _runMenuAction(() => onDeletePermanently(entry)),
          child: const Text('彻底删除'),
        ),
      ],
      child: child,
    );
  }

  void _toggleEntry(GlobalTrashBrowserEntry entry) {
    if (busyIds.contains(entry.id)) {
      return;
    }
    if (_dismissActiveContextMenu()) {
      return;
    }
    onToggleSelection(entry);
  }

  bool _dismissActiveContextMenu() {
    return DesktopContextMenuRegistry.dismiss(_globalTrashContextMenuGroup);
  }

  void _runMenuAction(VoidCallback action) {
    DesktopContextMenuRegistry.dismiss(_globalTrashContextMenuGroup);
    action();
  }

  Widget _buildLoadingRow(ShadThemeData theme) {
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

class _GlobalTrashHeader extends StatelessWidget {
  const _GlobalTrashHeader({
    required this.theme,
    required this.showBucketColumn,
    required this.allSelected,
    required this.partiallySelected,
    required this.onToggleSelectAll,
  });

  final ShadThemeData theme;
  final bool showBucketColumn;
  final bool allSelected;
  final bool partiallySelected;
  final VoidCallback onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.7);
    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.mutedForeground,
      letterSpacing: 0.2,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 0.6)),
      ),
      child: Row(
        children: [
          _HeaderSelectionIndicator(
            allSelected: allSelected,
            partiallySelected: partiallySelected,
            onTap: onToggleSelectAll,
          ),
          const SizedBox(width: 10),
          const SizedBox(width: 32),
          const SizedBox(width: 12),
          Expanded(child: Text('名称', style: labelStyle)),
          if (showBucketColumn) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: GlobalTrashBrowser._bucketColumnWidth,
              child: Text('存储桶', textAlign: TextAlign.right, style: labelStyle),
            ),
            const SizedBox(width: 16),
          ] else
            const SizedBox(width: 16),
          SizedBox(
            width: FileListTile.modifiedColumnWidth,
            child: Text('删除时间', textAlign: TextAlign.right, style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: TrashRowActions.actionColumnWidth,
            child: Text('操作', textAlign: TextAlign.right, style: labelStyle),
          ),
        ],
      ),
    );
  }
}

class _HeaderSelectionIndicator extends StatelessWidget {
  const _HeaderSelectionIndicator({
    required this.allSelected,
    required this.partiallySelected,
    required this.onTap,
  });

  final bool allSelected;
  final bool partiallySelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accent = theme.colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: allSelected || partiallySelected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: allSelected || partiallySelected
                ? accent
                : theme.colorScheme.border.withValues(alpha: 0.9),
            width: 1.2,
          ),
        ),
        child: allSelected
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : partiallySelected
            ? const Icon(Icons.remove, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}
