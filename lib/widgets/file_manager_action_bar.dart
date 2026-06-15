// 文件管理操作栏：集中展示搜索和常用对象操作。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerActionBar extends StatelessWidget {
  const FileManagerActionBar({
    super.key,
    required this.theme,
    required this.isGrid,
    required this.onToggleView,
    this.searchController,
    this.searchPlaceholder = '搜索',
    this.searchEnabled = true,
    this.selectedCount = 0,
    this.batchDownloadEnabled = false,
    this.showingTrash = false,
    this.onCreateDirectory,
    this.onUpload,
    this.onOpenTrash,
    this.onCloseTrash,
    this.onClearTrash,
    this.trashOpenLabel = '回收站',
    this.trashCloseLabel = '返回文件',
    this.onBatchDownload,
    this.onBatchDelete,
    this.onClearSelection,
  });

  final ShadThemeData theme;
  final bool isGrid;
  final VoidCallback onToggleView;
  final TextEditingController? searchController;
  final String searchPlaceholder;
  final bool searchEnabled;
  final int selectedCount;
  final bool batchDownloadEnabled;
  final bool showingTrash;
  final VoidCallback? onCreateDirectory;
  final VoidCallback? onUpload;
  final VoidCallback? onOpenTrash;
  final VoidCallback? onCloseTrash;
  final VoidCallback? onClearTrash;
  final String trashOpenLabel;
  final String trashCloseLabel;
  final VoidCallback? onBatchDownload;
  final VoidCallback? onBatchDelete;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (searchController != null) ...[
          SizedBox(
            width: 320,
            child: ShadInput(
              controller: searchController,
              enabled: searchEnabled,
              placeholder: Text(searchPlaceholder),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: _ActionButtons(
                theme: theme,
                isGrid: isGrid,
                onToggleView: onToggleView,
                selectedCount: selectedCount,
                batchDownloadEnabled: batchDownloadEnabled,
                showingTrash: showingTrash,
                onCreateDirectory: onCreateDirectory,
                onUpload: onUpload,
                onOpenTrash: onOpenTrash,
                onCloseTrash: onCloseTrash,
                onClearTrash: onClearTrash,
                trashOpenLabel: trashOpenLabel,
                trashCloseLabel: trashCloseLabel,
                onBatchDownload: onBatchDownload,
                onBatchDelete: onBatchDelete,
                onClearSelection: onClearSelection,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.theme,
    required this.isGrid,
    required this.onToggleView,
    required this.selectedCount,
    required this.batchDownloadEnabled,
    required this.showingTrash,
    required this.onCreateDirectory,
    required this.onUpload,
    required this.onOpenTrash,
    required this.onCloseTrash,
    required this.onClearTrash,
    required this.trashOpenLabel,
    required this.trashCloseLabel,
    required this.onBatchDownload,
    required this.onBatchDelete,
    required this.onClearSelection,
  });

  final ShadThemeData theme;
  final bool isGrid;
  final VoidCallback onToggleView;
  final int selectedCount;
  final bool batchDownloadEnabled;
  final bool showingTrash;
  final VoidCallback? onCreateDirectory;
  final VoidCallback? onUpload;
  final VoidCallback? onOpenTrash;
  final VoidCallback? onCloseTrash;
  final VoidCallback? onClearTrash;
  final String trashOpenLabel;
  final String trashCloseLabel;
  final VoidCallback? onBatchDownload;
  final VoidCallback? onBatchDelete;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    final inSelectionMode = selectedCount > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (inSelectionMode) ...[
          _selectionBadge(primary),
          const SizedBox(width: 6),
          _actionButton(
            label: '批量下载',
            icon: LucideIcons.download,
            color: primary,
            onPressed: batchDownloadEnabled ? onBatchDownload : null,
          ),
          const SizedBox(width: 6),
          _actionButton(
            label: '批量删除',
            icon: LucideIcons.trash2,
            color: primary,
            onPressed: onBatchDelete,
          ),
          const SizedBox(width: 6),
          _actionButton(
            label: '取消选择',
            icon: LucideIcons.x,
            color: primary,
            onPressed: onClearSelection,
          ),
        ] else ...[
          _iconButton(
            icon: isGrid ? LucideIcons.list : LucideIcons.layoutGrid,
            color: primary,
            onPressed: onToggleView,
          ),
          if (onOpenTrash != null || onCloseTrash != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: showingTrash ? trashCloseLabel : trashOpenLabel,
              icon: showingTrash ? LucideIcons.folderOpen : LucideIcons.trash2,
              color: primary,
              onPressed: showingTrash ? onCloseTrash : onOpenTrash,
            ),
          ],
          if (showingTrash && onClearTrash != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '清空回收站',
              icon: LucideIcons.trash,
              color: theme.colorScheme.destructive,
              onPressed: onClearTrash,
            ),
          ],
          if (onCreateDirectory != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '新建目录',
              icon: Icons.create_new_folder_rounded,
              color: primary,
              onPressed: onCreateDirectory,
            ),
          ],
          if (onUpload != null) ...[
            const SizedBox(width: 6),
            _actionButton(
              label: '上传',
              icon: LucideIcons.upload,
              color: primary,
              onPressed: onUpload,
            ),
          ],
        ],
      ],
    );
  }

  Widget _selectionBadge(Color color) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '已选 $selectedCount 项',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      onPressed: onPressed,
      child: Icon(icon, size: 14, color: color),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
    );
  }
}
