// Finder 风格文件列表行：左侧名称，右侧固定尺寸/修改时间列。

import 'package:flutter/material.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 文件管理页的列表项。
class FileListTile extends StatefulWidget {
  const FileListTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitleLabel = '',
    this.sizeLabel = '',
    this.statusWidget,
    this.modifiedLabel = '',
    required this.onTap,
    this.onDoubleTap,
    this.onTitleTap,
    this.onSelectionTap,
    this.isSelected = false,
    this.showSelectionControl = false,
    this.showDivider = true,
    this.deleting = false,
    this.trailing,
    this.sizeColumnWidthOverride = FileListTile.sizeColumnWidth,
  });

  static const double sizeColumnWidth = 96;
  static const double statusColumnWidth = 112;
  static const double modifiedColumnWidth = 154;

  final Widget leading;
  final String title;
  final String subtitleLabel;
  final String sizeLabel;
  final Widget? statusWidget;
  final String modifiedLabel;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTitleTap;
  final VoidCallback? onSelectionTap;
  final bool isSelected;
  final bool showSelectionControl;
  final bool showDivider;
  final bool deleting;
  final Widget? trailing;
  final double sizeColumnWidthOverride;

  @override
  State<FileListTile> createState() => _FileListTileState();
}

class _FileListTileState extends State<FileListTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interactionColors = ListInteractionColors.fromTheme(theme);
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.55);
    final backgroundColor = interactionColors.rowBackground(
      selected: widget.isSelected,
      hovered: _hovered,
      pressed: _pressed,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.deleting ? null : widget.onTap,
        onTapDown: widget.deleting
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: widget.deleting
            ? null
            : (_) => setState(() => _pressed = false),
        onTapCancel: widget.deleting
            ? null
            : () => setState(() => _pressed = false),
        onDoubleTap: widget.deleting ? null : widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: widget.showDivider
                ? Border(bottom: BorderSide(color: dividerColor, width: 0.6))
                : null,
          ),
          child: Row(
            children: [
              if (widget.showSelectionControl) ...[
                ListSelectionControl(
                  selected: widget.isSelected,
                  onTap: widget.onSelectionTap,
                ),
                const SizedBox(width: 10),
              ],
              widget.leading,
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onTitleTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: widget.deleting
                                ? theme.colorScheme.mutedForeground
                                : theme.colorScheme.foreground,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.subtitleLabel.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitleLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.mutedForeground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: widget.sizeColumnWidthOverride,
                child: Text(
                  widget.sizeLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: widget.deleting
                        ? theme.colorScheme.primary
                        : theme.colorScheme.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.statusWidget != null) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: FileListTile.statusColumnWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: widget.statusWidget!,
                  ),
                ),
              ],
              const SizedBox(width: 16),
              if (widget.trailing != null)
                widget.trailing!
              else
                SizedBox(
                  width: FileListTile.modifiedColumnWidth,
                  child: Text(
                    widget.modifiedLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: widget.deleting
                          ? theme.colorScheme.primary
                          : theme.colorScheme.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
