// Touch-first file, bucket, and recycle-bin rows for the Android file page.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:remote_storage/widgets/file_manager_empty_state.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Which data set is rendered by [MobileFileManagerBrowser].
enum MobileFileManagerSection { buckets, objects, trash }

/// Touch-first list for buckets, objects, and recycle-bin entries.
class MobileFileManagerBrowser extends StatelessWidget {
  const MobileFileManagerBrowser({
    super.key,
    required this.section,
    required this.scrollController,
    this.buckets = const <FileManagerBucketEntry>[],
    this.objects = const <ObjectInfo>[],
    this.trashItems = const <TrashItem>[],
    this.hasMore = false,
    this.loadingMore = false,
    this.selectedKeys = const <String>{},
    this.onOpenBucket,
    this.onBucketMenu,
    this.onOpenDirectory,
    this.onOpenFile,
    this.onNavigateUp,
    this.onObjectMenu,
    this.onToggleSelection,
    this.onTrashMenu,
    this.emptyText = '此处为空',
  });

  final MobileFileManagerSection section;
  final ScrollController scrollController;
  final List<FileManagerBucketEntry> buckets;
  final List<ObjectInfo> objects;
  final List<TrashItem> trashItems;
  final bool hasMore;
  final bool loadingMore;
  final Set<String> selectedKeys;
  final ValueChanged<FileManagerBucketEntry>? onOpenBucket;
  final ValueChanged<FileManagerBucketEntry>? onBucketMenu;
  final ValueChanged<String>? onOpenDirectory;
  final ValueChanged<ObjectInfo>? onOpenFile;
  final VoidCallback? onNavigateUp;
  final ValueChanged<ObjectInfo>? onObjectMenu;
  final ValueChanged<ObjectInfo>? onToggleSelection;
  final ValueChanged<TrashItem>? onTrashMenu;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      MobileFileManagerSection.buckets => _buildBuckets(context),
      MobileFileManagerSection.objects => _buildObjects(context),
      MobileFileManagerSection.trash => _buildTrash(context),
    };
  }

  Widget _buildBuckets(BuildContext context) {
    if (buckets.isEmpty) return _empty(context, LucideIcons.database);
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 92),
      itemCount: buckets.length,
      separatorBuilder: (_, index) => _divider(context),
      itemBuilder: (context, index) {
        final bucket = buckets[index];
        return MobileFileManagerRow(
          key: ValueKey('mobile-bucket-${bucket.id}'),
          // Keep the established mobile bucket artwork rather than inheriting
          // the desktop WhiteSur icon family.
          leading: LocalCloudPanFileIcon(
            name: bucket.label,
            isBucket: true,
            size: 58,
          ),
          title: bucket.label,
          subtitle: bucket.sourceLabel,
          detail: _bucketQuota(context, bucket),
          trailing: _rowMenu(
            context,
            tooltip: '存储桶操作',
            onPressed: onBucketMenu == null
                ? null
                : () => onBucketMenu!(bucket),
          ),
          onTap: onOpenBucket == null ? null : () => onOpenBucket!(bucket),
        );
      },
    );
  }

  Widget _buildObjects(BuildContext context) {
    if (objects.isEmpty) return _empty(context, LucideIcons.folderOpen);
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 92),
      itemCount: objects.length + (loadingMore ? 1 : 0),
      separatorBuilder: (_, index) => _divider(context),
      itemBuilder: (context, index) {
        if (index >= objects.length) return _loadingRow();
        final object = objects[index];
        final isParent = object.key == '../';
        final selected = selectedKeys.contains(object.key);
        final selectionMode = selectedKeys.isNotEmpty;
        final subtitle = isParent
            ? '返回上一级'
            : object.isDir
            ? '文件夹'
            : '${object.sizeText}${object.lastModified.isEmpty ? '' : '  ${object.lastModified}'}';
        return MobileFileManagerRow(
          key: ValueKey('mobile-object-${object.key}'),
          leading: LocalCloudPanFileIcon(
            name: object.displayName,
            isDirectory: object.isDir || isParent,
            size: 52,
          ),
          title: isParent ? '..' : object.displayName,
          subtitle: subtitle,
          leadingControl: selectionMode && !isParent
              ? ListSelectionControl(
                  selected: selected,
                  onTap: onToggleSelection == null
                      ? null
                      : () => onToggleSelection!(object),
                )
              : null,
          trailing: isParent
              ? null
              : _rowMenu(
                  context,
                  tooltip: '文件操作',
                  onPressed: onObjectMenu == null
                      ? null
                      : () => onObjectMenu!(object),
                ),
          onTap: () {
            if (selectionMode && !isParent) {
              onToggleSelection?.call(object);
            } else if (isParent) {
              onNavigateUp?.call();
            } else if (object.isDir) {
              onOpenDirectory?.call(object.key);
            } else {
              onOpenFile?.call(object);
            }
          },
          onLongPress: isParent || onToggleSelection == null
              ? null
              : () => onToggleSelection!(object),
          selected: selected,
        );
      },
    );
  }

  Widget _buildTrash(BuildContext context) {
    if (trashItems.isEmpty) return _empty(context, LucideIcons.trash2);
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 92),
      itemCount: trashItems.length + (loadingMore ? 1 : 0),
      separatorBuilder: (_, index) => _divider(context),
      itemBuilder: (context, index) {
        if (index >= trashItems.length) return _loadingRow();
        final item = trashItems[index];
        return MobileFileManagerRow(
          key: ValueKey('mobile-trash-${item.id}'),
          leading: Icon(
            item.isDir ? LucideIcons.folderArchive : LucideIcons.fileX2,
            size: 44,
            color: _theme(context).colorScheme.mutedForeground,
          ),
          title: item.name,
          subtitle: '${item.sizeText}  ${item.deletedAt}',
          trailing: _rowMenu(
            context,
            tooltip: '回收站操作',
            onPressed: onTrashMenu == null ? null : () => onTrashMenu!(item),
          ),
          onTap: onTrashMenu == null ? null : () => onTrashMenu!(item),
        );
      },
    );
  }

  Widget _empty(BuildContext context, IconData icon) {
    return FileManagerEmptyState(
      theme: _theme(context),
      icon: icon,
      text: emptyText,
    );
  }

  Widget _divider(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.6,
      color: _theme(context).colorScheme.border.withValues(alpha: 0.65),
    );
  }

  Widget _loadingRow() {
    return const SizedBox(
      height: 58,
      child: Center(child: AppLoadingIndicator(strokeWidth: 2)),
    );
  }

  Widget _rowMenu(
    BuildContext context, {
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return AppTooltip(
      message: tooltip,
      child: ShadIconButton.ghost(
        width: 44,
        height: 44,
        iconSize: 21,
        icon: const Icon(LucideIcons.ellipsisVertical),
        onPressed: onPressed,
      ),
    );
  }

  Widget _bucketQuota(BuildContext context, FileManagerBucketEntry bucket) {
    final theme = _theme(context);
    final custom = bucket.config
        .bucketSettingsFor(bucket.bucket.name)
        .customQuotaBytes;
    final total = custom > 0 ? custom : bucket.bucket.quotaBytes;
    if (total <= 0) return const SizedBox.shrink();
    final label = bucket.bucket.quotaKnown
        ? '${formatBytes(bucket.bucket.usedBytes)} / ${formatBytes(total)}'
        : '配额 ${formatBytes(total)}';
    final progress = bucket.bucket.quotaKnown
        ? (bucket.bucket.usedBytes / total).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: theme.colorScheme.border.withValues(alpha: 0.55),
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  ShadThemeData _theme(BuildContext context) => ShadTheme.of(context);
}

/// A larger, divider-separated row designed for thumb interaction.
class MobileFileManagerRow extends StatefulWidget {
  const MobileFileManagerRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.detail,
    this.leadingControl,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? detail;
  final Widget? leadingControl;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  State<MobileFileManagerRow> createState() => _MobileFileManagerRowState();
}

class _MobileFileManagerRowState extends State<MobileFileManagerRow> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interactions = ListInteractionColors.fromTheme(theme);
    final interactive = widget.onTap != null;
    return MouseRegion(
      cursor: interactive && _hovered
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: interactive ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: interactive
            ? () => setState(() => _pressed = false)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          decoration: BoxDecoration(
            color: interactions.rowBackground(
              selected: widget.selected,
              hovered: interactive && _hovered,
              pressed: interactive && _pressed,
            ),
          ),
          child: Row(
            children: [
              if (widget.leadingControl != null) ...[
                SizedBox(
                  width: 28,
                  child: Center(child: widget.leadingControl),
                ),
                const SizedBox(width: 4),
              ],
              SizedBox(
                width: 64,
                height: 64,
                child: Center(child: widget.leading),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                    if (widget.detail != null) ...[
                      const SizedBox(height: 4),
                      widget.detail!,
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 4),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
