// 文件管理操作栏：搜索改为悬浮弹出式，常用对象操作平铺在右侧。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerActionBar extends StatelessWidget {
  const FileManagerActionBar({
    super.key,
    required this.theme,
    required this.isGrid,
    required this.onToggleView,
    this.showViewToggle = true,
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
  final bool showViewToggle;
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
    // 搜索按钮固定在最左侧（左操作区），功能按钮在右侧右对齐。
    return Row(
      children: [
        if (searchController != null) ...[
          _SearchPopoverButton(
            theme: theme,
            searchController: searchController!,
            placeholder: searchPlaceholder,
            enabled: searchEnabled,
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
                showViewToggle: showViewToggle,
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
    required this.showViewToggle,
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
  final bool showViewToggle;
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
          if (showViewToggle)
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

/// 搜索按钮：点击弹出悬浮搜索框，绑定外部 [searchController] 做即时过滤。
/// 有搜索词时图标高亮（primary 色），无内容时用默认前景色。
class _SearchPopoverButton extends StatefulWidget {
  const _SearchPopoverButton({
    required this.theme,
    required this.searchController,
    required this.placeholder,
    required this.enabled,
  });

  final ShadThemeData theme;
  final TextEditingController searchController;
  final String placeholder;
  final bool enabled;

  @override
  State<_SearchPopoverButton> createState() => _SearchPopoverButtonState();
}

class _SearchPopoverButtonState extends State<_SearchPopoverButton> {
  late final ShadPopoverController _controller;
  late final FocusNode _focusNode;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = ShadPopoverController();
    _focusNode = FocusNode();
    _hasText = widget.searchController.text.isNotEmpty;
    widget.searchController.addListener(_onSearchChanged);
    // popover 打开时把焦点放到搜索框，关闭时清空焦点。
    _controller.addListener(_onPopoverChanged);
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onSearchChanged);
    _controller.removeListener(_onPopoverChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final has = widget.searchController.text.isNotEmpty;
    if (has != _hasText) {
      setState(() => _hasText = has);
    }
  }

  void _onPopoverChanged() {
    if (_controller.isOpen) {
      // 等一帧让 popover 内容渲染完，再抢焦点。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final iconColor = _hasText
        ? theme.colorScheme.primary
        : theme.colorScheme.foreground;
    return ShadPopover(
      controller: _controller,
      closeOnTapOutside: true,
      reverseDuration: Duration.zero,
      // 搜索框从按钮右侧弹出，而非下方，避免悬浮感太独立。
      anchor: const ShadAnchor(offset: Offset(4, 0)),
      popover: (context) => _buildSearchField(theme),
      child: ShadButton.ghost(
        size: ShadButtonSize.sm,
        onPressed: widget.enabled
            ? () => _controller.isOpen ? _controller.hide() : _controller.show()
            : null,
        child: Icon(LucideIcons.search, size: 14, color: iconColor),
      ),
    );
  }

  Widget _buildSearchField(ShadThemeData theme) {
    return SizedBox(
      width: 280,
      child: ShadInput(
        controller: widget.searchController,
        focusNode: _focusNode,
        enabled: widget.enabled,
        placeholder: Text(widget.placeholder),
        trailing: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.searchController,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () => widget.searchController.clear(),
              child: Icon(
                LucideIcons.x,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
            );
          },
        ),
      ),
    );
  }
}
