// Unified task rows render effective remote operations with optional raw detail.
// Layout contract: the title text column starts at 80px from the row edge in
// selection mode / desktop (12 padding + 18 checkbox + 10 gap + 28 kind chip +
// 12 gap); the expanded detail block insets to the same value so it aligns with
// the title. Android browse rows drop the checkbox column (two-state selection
// model, title starts at 52px) but never expand inline — task details open from
// the selection bar's 详情 action instead (任务详情 sheet). The row divider is
// the full-width FileListTile hairline (0.55/0.6).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:remote_storage/widgets/fitting_file_name_text.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:remote_storage/widgets/mobile_selection_chrome.dart';
import 'package:remote_storage/widgets/remote_task_details.dart';
import 'package:remote_storage/widgets/remote_task_style_helpers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RemoteTaskStatusBadge extends StatelessWidget {
  const RemoteTaskStatusBadge({super.key, required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = remoteTaskStatusColor(theme, task.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Text(
        remoteTaskStatusLabel(task),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class RemoteTaskRow extends StatefulWidget {
  const RemoteTaskRow({
    super.key,
    required this.task,
    required this.selected,
    required this.onToggleSelected,
    this.onCancel,
    this.onRetry,
    this.onTrigger,
    this.onExpanded,
    this.showDivider = true,
    this.selectionMode = false,
  });

  final RemoteTask task;
  final bool selected;
  final VoidCallback onToggleSelected;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onTrigger;
  final ValueChanged<bool>? onExpanded;
  final bool showDivider;

  /// Android 两态选择模型:选中态(页面存在选择)行首显示勾选控件、行点击
  /// 切换选中;浏览态行尾显示选择圆点、行点击展开/收起明细。桌面忽略此
  /// 参数(行首常驻控件 + 行点击切换选中 + 内联图标动作)。
  final bool selectionMode;

  @override
  State<RemoteTaskRow> createState() => _RemoteTaskRowState();
}

class _RemoteTaskRowState extends State<RemoteTaskRow> {
  bool _hovered = false;
  bool _pressed = false;
  bool _expanded = false;
  bool _acting = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = ListInteractionColors.fromTheme(theme);
    final task = widget.task;
    // All unsettled-but-moving states get one compact spinner; the badge text
    // stays static, so this is the row's only motion cue.
    final showsSpinner =
        task.status == RemoteTaskStatus.running ||
        task.status == RemoteTaskStatus.verifying ||
        task.status == RemoteTaskStatus.cancelRequested ||
        task.status == RemoteTaskStatus.reconciling;
    final android = defaultTargetPlatform == TargetPlatform.android;
    final browseMode = android && !widget.selectionMode;

    return MouseRegion(
      cursor: _hovered ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 行点击在所有状态都是切换选中(两态模型;任务无浏览态主操作,
        // 明细经选中态动作条的「详情」打开)。
        onTap: widget.onToggleSelected,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          // 行分隔线与 FileListTile(文件/回收站行)同规格:全宽底部发丝线。
          decoration: BoxDecoration(
            color: colors.rowBackground(
              selected: widget.selected,
              hovered: _hovered,
              pressed: _pressed,
            ),
            border: widget.showDivider
                ? Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.border.withValues(alpha: 0.55),
                      width: 0.6,
                    ),
                  )
                : null,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    if (!browseMode) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: ListSelectionControl(
                          selected: widget.selected,
                          onTap: widget.onToggleSelected,
                          touchTargetSize: android ? 48 : 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    _KindIconChip(kind: task.kind),
                    const SizedBox(width: 12),
                    Expanded(child: _TaskText(task: task)),
                    const SizedBox(width: 16),
                    _TaskRightSide(
                      task: task,
                      showsSpinner: showsSpinner,
                      acting: _acting,
                      browseMode: browseMode,
                      onSelect: widget.onToggleSelected,
                      onCancel: widget.onCancel == null
                          ? null
                          : () => _run(widget.onCancel!),
                      onRetry: widget.onRetry == null
                          ? null
                          : () => _run(widget.onRetry!),
                      onTrigger: widget.onTrigger == null
                          ? null
                          : () => _run(widget.onTrigger!),
                      onExpand: _toggleExpanded,
                      expanded: _expanded,
                    ),
                  ],
                ),
              ),
              if (_expanded) RemoteTaskDetails(task: task),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _toggleExpanded() {
    if (!mounted) return;
    setState(() => _expanded = !_expanded);
    widget.onExpanded?.call(_expanded);
  }
}

/// Rounded chip behind the kind icon: gives every operation type an instant
/// color identity that also reappears as the detail-panel accent.
class _KindIconChip extends StatelessWidget {
  const _KindIconChip({required this.kind});

  final RemoteTaskKind kind;

  @override
  Widget build(BuildContext context) {
    final iconColor = remoteTaskKindColor(kind);
    // Tooltip carries the op verb that no longer lives in the row title.
    return AppTooltip(
      message: remoteTaskKindLabel(kind),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(remoteTaskKindIcon(kind), size: 14, color: iconColor),
      ),
    );
  }
}

class _TaskText extends StatelessWidget {
  const _TaskText({required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    // Title shows only the entry name (icon chip carries the op type); the
    // verb, full path, and bucket are detail-panel lines.
    final subtitle = remoteTaskSubtitle(task);
    // Android 对齐移动列表基线（紧凑标题 14sp / 副标题 12sp，与文件管理、
    // 回收站的 compact 行一致）；桌面保持 13/11 的密集节奏。
    final touch = defaultTargetPlatform == TargetPlatform.android;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Android 走 FittingFileNameText：放得下原样（像素感知快路径），
        // 放不下退到 compactDisplayName 的 14 字符预算（任务行最窄）；
        // 桌面行宽足够，保持完整名称。
        touch
            ? FittingFileNameText(
                name: remoteTaskEntryName(task),
                truncationMaxLength: 14,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.foreground,
                ),
              )
            : Text(
                remoteTaskEntryName(task),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.foreground,
                ),
              ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: touch ? 12 : 11,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}

/// Right-side controls: activity spinner, status badge, then either the
/// browse-mode select dot (Android) or the desktop inline icon actions.
class _TaskRightSide extends StatelessWidget {
  const _TaskRightSide({
    required this.task,
    required this.showsSpinner,
    required this.acting,
    required this.browseMode,
    required this.onSelect,
    required this.onCancel,
    required this.onRetry,
    required this.onTrigger,
    required this.onExpand,
    required this.expanded,
  });

  final RemoteTask task;
  final bool showsSpinner;
  final bool acting;

  /// Android browse state: trailing is the select dot (two-state model);
  /// desktop keeps inline icons + details chevron.
  final bool browseMode;
  final VoidCallback onSelect;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onTrigger;
  final VoidCallback onExpand;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final android = defaultTargetPlatform == TargetPlatform.android;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showsSpinner) ...[
          AppLoadingIndicator(
            size: 12,
            strokeWidth: 1.6,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
        ],
        RemoteTaskStatusBadge(task: task),
        const SizedBox(width: 8),
        if (android) ...[
          // Android:浏览态行尾是选择圆点;选中态动作在底部动作条,行尾
          // 只剩状态徽标与 spinner(明细经「详情」动作打开)。
          if (browseMode) MobileRowSelectDot(onTap: onSelect),
        ] else ...[
          if (onCancel != null)
            _iconAction('取消任务', LucideIcons.circleX, onCancel!),
          if (onRetry != null)
            _iconAction('重试任务', LucideIcons.refreshCw, onRetry!),
          if (onTrigger != null)
            _iconAction('立即执行', LucideIcons.play, onTrigger!),
          _iconAction(
            expanded ? '收起明细' : '查看明细',
            expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            onExpand,
          ),
        ],
        if (acting) ...[
          const SizedBox(width: 8),
          const AppLoadingIndicator(size: 14, strokeWidth: 1.6),
        ],
      ],
    );
  }

  Widget _iconAction(String message, IconData icon, VoidCallback onPressed) {
    // Touch rows need the full 48dp target; desktop keeps the compact 28dp.
    final touch = defaultTargetPlatform == TargetPlatform.android;
    return AppTooltip(
      message: message,
      child: ShadIconButton.ghost(
        icon: Icon(icon, size: 15),
        width: touch ? 48 : 28,
        height: touch ? 48 : 28,
        iconSize: 15,
        onPressed: acting ? null : onPressed,
      ),
    );
  }
}
