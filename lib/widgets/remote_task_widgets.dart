// Unified task rows render effective remote operations with optional raw detail.
// Layout contract: the title text column starts at 80px from the row edge
// (12 padding + 18 checkbox + 10 gap + 28 kind chip + 12 gap); the expanded
// detail block and row divider inset to the same value so all rows align.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/remote_task_display.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:remote_storage/widgets/remote_task_style_helpers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Left inset (px) at which row content (title/details/divider) aligns.
const double _taskContentIndent = 80;

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
  });

  final RemoteTask task;
  final bool selected;
  final VoidCallback onToggleSelected;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onTrigger;
  final ValueChanged<bool>? onExpanded;
  final bool showDivider;

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

    return MouseRegion(
      cursor: _hovered ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggleSelected,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: colors.rowBackground(
            selected: widget.selected,
            hovered: _hovered,
            pressed: _pressed,
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
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: ListSelectionControl(
                        selected: widget.selected,
                        onTap: widget.onToggleSelected,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _KindIconChip(kind: task.kind),
                    const SizedBox(width: 12),
                    Expanded(child: _TaskText(task: task)),
                    const SizedBox(width: 16),
                    _TaskRightSide(
                      task: task,
                      showsSpinner: showsSpinner,
                      acting: _acting,
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
              if (_expanded) _TaskDetails(task: task),
              if (widget.showDivider)
                Padding(
                  padding: const EdgeInsets.only(
                    left: _taskContentIndent,
                    right: 12,
                  ),
                  child: Divider(
                    height: 1,
                    color: theme.colorScheme.border.withValues(alpha: 0.45),
                  ),
                ),
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
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(remoteTaskKindIcon(kind), size: 14, color: iconColor),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          remoteTaskEntryName(task),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
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
              fontSize: 11,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}

/// Right-side controls: activity spinner, status badge, then ghost actions.
class _TaskRightSide extends StatelessWidget {
  const _TaskRightSide({
    required this.task,
    required this.showsSpinner,
    required this.acting,
    required this.onCancel,
    required this.onRetry,
    required this.onTrigger,
    required this.onExpand,
    required this.expanded,
  });

  final RemoteTask task;
  final bool showsSpinner;
  final bool acting;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onTrigger;
  final VoidCallback onExpand;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
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
        if (acting) ...[
          const SizedBox(width: 8),
          const AppLoadingIndicator(size: 14, strokeWidth: 1.6),
        ],
      ],
    );
  }

  Widget _iconAction(String message, IconData icon, VoidCallback onPressed) {
    return AppTooltip(
      message: message,
      child: ShadIconButton.ghost(
        icon: Icon(icon, size: 15),
        width: 28,
        height: 28,
        iconSize: 15,
        onPressed: acting ? null : onPressed,
      ),
    );
  }
}

/// Expanded detail block under a row. A thin kind-colored accent bar on the
/// left ties the panel to its row; body uses muted key/value lines.
class _TaskDetails extends StatelessWidget {
  const _TaskDetails({required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final events = task.events;
    final accent = remoteTaskKindColor(task.kind);
    return Container(
      margin: const EdgeInsets.only(
        left: _taskContentIndent,
        right: 12,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Op context moved out of the row title lives here.
                    _detailLine(context, '操作', remoteTaskKindLabel(task.kind)),
                    if (task.bucket.trim().isNotEmpty)
                      _detailLine(context, '所属桶', task.bucket),
                    if (task.operationPath.isNotEmpty)
                      _detailLine(context, '完整路径', task.operationPath),
                    if (task.blockedReason.isNotEmpty)
                      _detailLine(
                        context,
                        '依赖',
                        task.blockedReason,
                        valueColor: Colors.amber.shade700,
                      ),
                    if (task.mountReadRange.isNotEmpty)
                      _detailLine(context, '读取范围', task.mountReadRange)
                    else if (task.phaseLabel.isNotEmpty)
                      _detailLine(context, '阶段', task.phaseLabel),
                    if (task.sourceTargetSummary.isNotEmpty)
                      _detailLine(context, '路径', task.sourceTargetSummary),
                    if (task.localPath.isNotEmpty)
                      _detailLine(context, '本地路径', task.localPath),
                    if (task.progress.currentKey.isNotEmpty &&
                        task.progress.currentFileTotalBytes > 0)
                      _detailLine(
                        context,
                        '当前文件',
                        '${task.progress.currentKey} '
                            '${formatBytes(task.progress.currentFileBytesCompleted)} / '
                            '${formatBytes(task.progress.currentFileTotalBytes)}',
                      ),
                    if (task.progress.currentPart > 0 &&
                        task.progress.totalParts > 0)
                      _detailLine(
                        context,
                        '分块',
                        '第 ${task.progress.currentPart} / ${task.progress.totalParts} 块'
                            '${task.progress.currentRange.isEmpty ? '' : ' · ${task.progress.currentRange}'}',
                      ),
                    if (task.error.isNotEmpty)
                      _detailLine(
                        context,
                        '错误',
                        task.error,
                        valueColor: theme.colorScheme.destructive,
                      ),
                    if (task.remoteOutcome.isNotEmpty)
                      _detailLine(context, '远端结果', task.remoteOutcome),
                    if (events.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final event in events) _eventLine(context, event),
                    ] else if (task.rawEventCount > 0)
                      _detailLine(context, '原始操作', '${task.rawEventCount} 条记录'),
                    if (task.physicalTaskIds.isNotEmpty)
                      _detailLine(
                        context,
                        '传输',
                        task.physicalTaskIds.join('  ·  '),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailLine(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final theme = ShadTheme.of(context);
    final base = valueColor ?? theme.colorScheme.mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      // No maxLines: this panel is the only full-text surface for long
      // provider errors and dependency reasons, so values must wrap.
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label：',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: base.withValues(alpha: 0.7),
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(fontSize: 11, color: base),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventLine(BuildContext context, RemoteTaskEvent event) {
    final theme = ShadTheme.of(context);
    final target = event.targetPath.isNotEmpty
        ? event.targetPath
        : event.sourcePath;
    final folded = event.folded ? '（已合并）' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Text(
        '#${event.sequence} ${event.kind} $target $folded',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontFamily: 'monospace',
          color: theme.colorScheme.mutedForeground.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
