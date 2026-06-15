// Finder 风格的文件网格单元：无边框、图标居中、名称压在图标下方。

import 'package:flutter/material.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 文件管理页的 Finder 风格网格项。
class FileGridItem extends StatelessWidget {
  static const double _selectionControlSize = 18;
  static const double _selectionControlInset = 24;
  static const double _titleSlotHeight = 30;

  const FileGridItem({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onDoubleTap,
    this.onTitleTap,
    this.onSelectionTap,
    this.isSelected = false,
    this.showSelectionControl = false,
    this.deleting = false,
    this.footer,
    this.bottomOverlay,
    this.contentWidth,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTitleTap;
  final VoidCallback? onSelectionTap;
  final bool isSelected;
  final bool showSelectionControl;
  final bool deleting;
  final Widget? footer;
  final Widget? bottomOverlay;
  final double? contentWidth;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interactionColors = ListInteractionColors.fromTheme(theme);
    return _HoverBuilder(
      builder: (hovered) {
        return GestureDetector(
          onTap: deleting ? null : onTap,
          onDoubleTap: deleting ? null : onDoubleTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: interactionColors.gridBackground(
                selected: isSelected,
                hovered: hovered,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    showSelectionControl ? _selectionControlInset : 4,
                    6,
                    showSelectionControl ? _selectionControlInset : 4,
                    bottomOverlay == null ? 6 : 30,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          leading,
                          const SizedBox(height: 4),
                          SizedBox(
                            height: _titleSlotHeight,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: onTitleTap,
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: deleting
                                          ? theme.colorScheme.mutedForeground
                                          : theme.colorScheme.foreground,
                                      height: 1.25,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 10,
                                color: deleting
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.mutedForeground,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (footer != null) ...[
                            const SizedBox(height: 6),
                            footer!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (showSelectionControl)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: _SelectionIndicator(
                      size: _selectionControlSize,
                      isSelected: isSelected,
                      hovered: hovered || isSelected,
                      onTap: onSelectionTap,
                    ),
                  ),
                if (bottomOverlay != null)
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 4,
                    child: Center(child: bottomOverlay!),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({
    required this.size,
    required this.isSelected,
    required this.hovered,
    required this.onTap,
  });

  final double size;
  final bool isSelected;
  final bool hovered;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interactionColors = ListInteractionColors.fromTheme(theme);
    final accent = theme.colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isSelected
              ? accent
              : hovered
              ? interactionColors.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? accent
                : theme.colorScheme.border.withValues(alpha: 0.9),
            width: 1.2,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}

/// 追踪鼠标 hover，用于 Finder 风格轻量反馈。
class _HoverBuilder extends StatefulWidget {
  const _HoverBuilder({required this.builder});

  final Widget Function(bool hovered) builder;

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}
