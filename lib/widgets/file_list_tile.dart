// Finder 风格文件列表行：左侧名称，右侧固定尺寸/修改时间列。

import 'package:flutter/material.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/utils/display_name.dart';

/// 文件管理页的列表项。
class FileListTile extends StatefulWidget {
  const FileListTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitleLabel = '',
    this.sizeLabel = '',
    this.sizeWidget,
    this.statusWidget,
    this.modifiedLabel = '',
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onTitleTap,
    this.onSelectionTap,
    this.isSelected = false,
    this.showSelectionControl = false,
    this.showDivider = true,
    this.deleting = false,
    this.dimmed = false,
    this.trailing,
    this.sizeColumnWidthOverride = FileListTile.sizeColumnWidth,
    this.compact = false,
  });

  static const double sizeColumnWidth = 96;
  static const double statusColumnWidth = 112;
  static const double modifiedColumnWidth = 154;

  final Widget leading;
  final String title;
  final String subtitleLabel;
  final String sizeLabel;
  final Widget? sizeWidget;
  final Widget? statusWidget;
  final String modifiedLabel;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  /// Optional touch affordance for row-level actions (for example Android
  /// long-press menus). Desktop context-menu wrappers remain the default.
  final VoidCallback? onLongPress;
  final VoidCallback? onTitleTap;
  final VoidCallback? onSelectionTap;
  final bool isSelected;
  final bool showSelectionControl;
  final bool showDivider;
  final bool deleting;

  /// 仅展示、不可选中的行（例如远端目录选择器中的文件）。
  final bool dimmed;
  final Widget? trailing;
  final double sizeColumnWidthOverride;
  final bool compact;

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
    final dimmed = widget.dimmed;
    final interactive = !dimmed && !widget.deleting;
    final showSizeColumn =
        widget.sizeColumnWidthOverride > 0 ||
        widget.sizeLabel.isNotEmpty ||
        widget.sizeWidget != null;
    final titleColor = widget.deleting
        ? theme.colorScheme.mutedForeground
        : dimmed
        ? theme.colorScheme.mutedForeground.withValues(alpha: 0.82)
        : theme.colorScheme.foreground;
    final metaColor = widget.deleting
        ? theme.colorScheme.primary
        : dimmed
        ? theme.colorScheme.mutedForeground.withValues(alpha: 0.72)
        : theme.colorScheme.mutedForeground;
    final backgroundColor = interactionColors.rowBackground(
      selected: widget.isSelected,
      hovered: interactive ? _hovered : false,
      pressed: interactive ? _pressed : false,
    );

    return MouseRegion(
      // Cursor is declared statically per interactivity instead of being driven
      // by the _hovered state field. A state-driven cursor (click only while
      // hovered) can get stuck on the pointing hand when the row is rebuilt or
      // unmounted while hovered, because onExit may not fire — the field then
      // stays true and the hand never clears. A constant cursor per row kind
      // has no state to get stuck.
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? widget.onTap : null,
        onLongPress: interactive ? widget.onLongPress : null,
        onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: interactive ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: interactive
            ? () => setState(() => _pressed = false)
            : null,
        onDoubleTap: interactive ? widget.onDoubleTap : null,
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
                  touchTargetSize: widget.compact
                      ? 48
                      : ListSelectionControl.visualSize,
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
                    onTap: interactive ? widget.onTitleTap : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          // 名称截断仅用于紧凑（Android 窄屏）行；桌面端
                          // 列表保持完整文件名。
                          widget.compact
                              ? compactDisplayName(widget.title)
                              : widget.title,
                          style: TextStyle(
                            // 14sp remains legible in compact touch rows;
                            // desktop keeps its denser 13sp list rhythm.
                            fontSize: widget.compact ? 14 : 13,
                            fontWeight: FontWeight.w500,
                            color: titleColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.subtitleLabel.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitleLabel,
                            style: TextStyle(
                              // Compact rows still need a readable secondary
                              // label at Android's smallest supported scale.
                              fontSize: widget.compact ? 12 : 11,
                              color: theme.colorScheme.mutedForeground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (widget.compact &&
                            (widget.sizeLabel.isNotEmpty ||
                                widget.modifiedLabel.isNotEmpty ||
                                widget.statusWidget != null)) ...[
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 8,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (widget.sizeLabel.isNotEmpty)
                                Text(
                                  widget.sizeLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: metaColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (widget.modifiedLabel.isNotEmpty)
                                Text(
                                  widget.modifiedLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: metaColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (widget.statusWidget != null)
                                widget.statusWidget!,
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (!widget.compact && showSizeColumn) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: widget.sizeColumnWidthOverride,
                  child:
                      widget.sizeWidget ??
                      Text(
                        widget.sizeLabel,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 11.5, color: metaColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                ),
              ],
              if (!widget.compact && widget.statusWidget != null) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: FileListTile.statusColumnWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: widget.statusWidget!,
                  ),
                ),
              ],
              if (!widget.compact) const SizedBox(width: 16),
              if (widget.compact && widget.trailing != null)
                widget.trailing!
              else if (!widget.compact && widget.trailing != null)
                widget.trailing!
              else if (!widget.compact)
                SizedBox(
                  width: FileListTile.modifiedColumnWidth,
                  child: Text(
                    widget.modifiedLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11.5, color: metaColor),
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
