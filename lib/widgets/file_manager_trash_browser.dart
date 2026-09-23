// 回收站浏览区：按 bucket 展示软删除项目，并提供恢复与彻底删除操作。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_grid_item.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/mobile_selection_chrome.dart';
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
    this.selectedIds = const <String>{},
    this.onToggleSelection,
  });

  final List<TrashItem> items;
  final bool isGrid;
  final ScrollController scrollController;
  final bool hasMore;
  final bool loadingMore;
  final ValueChanged<TrashItem> onRestore;
  final ValueChanged<TrashItem> onDeletePermanently;

  /// Android 两态选择模型的选中集(按 TrashItem.id)与切换回调;桌面不使用。
  final Set<String> selectedIds;
  final ValueChanged<TrashItem>? onToggleSelection;

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
        final isAndroid = Theme.of(context).platform == TargetPlatform.android;
        final compact = isAndroid || constraints.maxWidth < 600;
        // Android 两态选择模型:浏览态行尾选择圆点、行点击进入选中;选中态
        // 行首勾选控件、行点击切换,动作在页面底部动作条。桌面(含窄窗口)
        // 保持 点击恢复 + 行尾内联动作按钮。
        final selectionActive = isAndroid && selectedIds.isNotEmpty;
        final listBody = Column(
          children: [
            if (isAndroid)
              const SizedBox.shrink()
            else if (compact)
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
                      onTap: isAndroid
                          ? () => onToggleSelection?.call(item)
                          : () => onRestore(item),
                      onSelectionTap: isAndroid
                          ? () => onToggleSelection?.call(item)
                          : null,
                      isSelected: selectedIds.contains(item.id),
                      showSelectionControl: selectionActive,
                      showDivider: index != items.length - 1 || loadingMore,
                      trailing: isAndroid
                          ? (selectionActive
                                ? null
                                : MobileRowSelectDot(
                                    onTap: () =>
                                        onToggleSelection?.call(item),
                                  ))
                          : compact
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
        );
        // Android 对齐文件管理移动基线（桶/对象列表同款）：回收站列表直接
        // 落在页面背景上，不再套带边框的卡片容器；桌面（含窄窗口）保持
        // 原卡片外观。
        if (isAndroid) {
          return listBody;
        }
        return ShadCard(padding: const EdgeInsets.all(4), child: listBody);
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
