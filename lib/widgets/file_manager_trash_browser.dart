// 回收站浏览区：按 bucket 展示软删除项目，并提供恢复与彻底删除操作。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/trash_row_actions.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/widgets/app_loading_indicator.dart';

const String _trashContextMenuGroup = 'file_manager_trash_browser';

class FileManagerTrashBrowser extends StatelessWidget {
  static const double _gridChildAspectRatio = 0.9;

  const FileManagerTrashBrowser({
    super.key,
    required this.items,
    required this.isGrid,
    required this.scrollController,
    required this.hasMore,
    required this.loadingMore,
    required this.onRestore,
    required this.onDeletePermanently,
  });

  final List<TrashItem> items;
  final bool isGrid;
  final ScrollController scrollController;
  final bool hasMore;
  final bool loadingMore;
  final ValueChanged<TrashItem> onRestore;
  final ValueChanged<TrashItem> onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    if (isGrid) {
      return _buildGrid(context);
    }
    return _buildList(context);
  }

  Widget _buildGrid(BuildContext context) {
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
            ...items.map(
              (item) => _wrapWithContextMenu(
                item,
                FileGridItem(
                  leading: Icon(
                    item.isDir ? LucideIcons.folderArchive : LucideIcons.fileX2,
                    size: 52,
                    color: ShadTheme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.82),
                  ),
                  title: item.name,
                  subtitle: item.sizeText,
                  contentWidth: 88,
                  onTap: () => onRestore(item),
                  footer: Text(
                    item.deletedAt,
                    style: TextStyle(
                      fontSize: 10,
                      color: ShadTheme.of(context).colorScheme.mutedForeground,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            if (loadingMore) _buildGridLoadingTile(context),
          ],
        );
      },
    );
  }

  Widget _wrapWithContextMenu(TrashItem item, Widget child) {
    return DesktopContextMenuRegion(
      groupId: _trashContextMenuGroup,
      items: [
        ShadContextMenuItem(
          onPressed: () => _runMenuAction(() => onRestore(item)),
          child: const Text('恢复'),
        ),
        ShadContextMenuItem(
          onPressed: () => _runMenuAction(() => onDeletePermanently(item)),
          child: const Text('彻底删除'),
        ),
      ],
      child: child,
    );
  }

  void _runMenuAction(VoidCallback action) {
    DesktopContextMenuRegistry.dismiss(_trashContextMenuGroup);
    action();
  }

  Widget _buildGridLoadingTile(BuildContext context) {
    final theme = ShadTheme.of(context);
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

  Widget _buildList(BuildContext context) {
    final theme = ShadTheme.of(context);
    final headerTextStyle = const TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = Theme.of(context).platform == TargetPlatform.android ||
            constraints.maxWidth < 600;
        return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          if (compact)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                ListSelectionControl(selected: false, onTap: () {}),
                const SizedBox(width: 10),
                const Text('全选'),
              ]),
            )
          else Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.border.withValues(alpha: 0.75),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 32),
                const SizedBox(width: 12),
                Expanded(child: Text('名称', style: headerTextStyle)),
                const SizedBox(width: 12),
                SizedBox(
                  width: compact ? 0 : FileListTile.sizeColumnWidth,
                  child: Text(
                    '原路径',
                    textAlign: TextAlign.right,
                    style: headerTextStyle,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: compact ? 0 : FileListTile.modifiedColumnWidth,
                  child: Text(
                    '删除时间',
                    textAlign: TextAlign.right,
                    style: headerTextStyle,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: compact ? 0 : TrashRowActions.actionColumnWidth,
                  child: Text(
                    '操作',
                    textAlign: TextAlign.right,
                    style: headerTextStyle,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: items.length + (loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= items.length) {
                  return _buildListLoadingRow(context);
                }
                final item = items[index];
                return _wrapWithContextMenu(
                  item,
                  FileListTile(
                    leading: Icon(
                      item.isDir
                          ? LucideIcons.folderArchive
                          : LucideIcons.fileX2,
                      size: 20,
                      color: theme.colorScheme.primary.withValues(alpha: 0.82),
                    ),
                    title: item.name,
                    sizeLabel: compact ? item.sizeText : item.originalKey,
                    modifiedLabel: item.deletedAt,
                    onTap: () => onRestore(item),
                    showDivider: index != items.length - 1 || loadingMore,
                    trailing: compact
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            ShadIconButton.ghost(icon: Icon(LucideIcons.rotateCcw, size: 18, color: theme.colorScheme.primary), onPressed: () => onRestore(item)),
                            ShadIconButton.ghost(icon: Icon(LucideIcons.trash2, size: 18, color: theme.colorScheme.mutedForeground), onPressed: () => onDeletePermanently(item)),
                          ])
                        : TrashRowActions(
                      deletedLabel: item.deletedAt,
                      busy: false,
                      onRestore: () => onRestore(item),
                      onDeletePermanently: () => onDeletePermanently(item),
                    ),
                    compact: compact,
                  ),
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

  Widget _buildListLoadingRow(BuildContext context) {
    final theme = ShadTheme.of(context);
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
