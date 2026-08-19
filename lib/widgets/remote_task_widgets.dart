// Unified task rows render effective remote operations with optional raw detail.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/remote_task_display.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RemoteTaskStatusBadge extends StatelessWidget {
  const RemoteTaskStatusBadge({super.key, required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = _statusColor(theme, task.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _statusLabel(task),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: ListSelectionControl(
                      selected: widget.selected,
                      onTap: widget.onToggleSelected,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      _kindIcon(task.kind),
                      size: 18,
                      color: _kindColor(task.kind),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _TaskText(task: task)),
                  const SizedBox(width: 12),
                  _TaskActions(
                    task: task,
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
              if (_expanded) _TaskDetails(task: task),
              if (widget.showDivider)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Divider(
                    height: 1,
                    color: theme.colorScheme.border.withValues(alpha: 0.55),
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

class _TaskText extends StatelessWidget {
  const _TaskText({required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final action = _kindLabel(task.kind);
    final target = task.operationPath;
    final subtitle = _taskSubtitle(task);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          target.isEmpty ? action : '$action $target',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _TaskActions extends StatelessWidget {
  const _TaskActions({
    required this.task,
    required this.acting,
    required this.onCancel,
    required this.onRetry,
    required this.onTrigger,
    required this.onExpand,
    required this.expanded,
  });

  final RemoteTask task;
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
        const SizedBox(width: 8),
        if (acting)
          SizedBox(
            width: 56,
            child: Center(
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ),
          )
        else
          RemoteTaskStatusBadge(task: task),
      ],
    );
  }

  Widget _iconAction(String message, IconData icon, VoidCallback onPressed) {
    return AppTooltip(
      message: message,
      child: ShadIconButton.ghost(
        icon: Icon(icon, size: 16),
        width: 28,
        height: 28,
        iconSize: 16,
        onPressed: acting ? null : onPressed,
      ),
    );
  }
}

class _TaskDetails extends StatelessWidget {
  const _TaskDetails({required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final events = task.events;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 40, top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.blockedReason.isNotEmpty)
            _detailLine('依赖', task.blockedReason),
          if (task.mountReadRange.isNotEmpty)
            _detailLine('读取范围', task.mountReadRange)
          else if (task.phaseLabel.isNotEmpty)
            _detailLine('阶段', task.phaseLabel),
          if (task.sourceTargetSummary.isNotEmpty)
            _detailLine('路径', task.sourceTargetSummary),
          if (task.localPath.isNotEmpty) _detailLine('本地路径', task.localPath),
          if (task.progress.currentKey.isNotEmpty &&
              task.progress.currentFileTotalBytes > 0)
            _detailLine(
              '当前文件',
              '${task.progress.currentKey} '
                  '${formatBytes(task.progress.currentFileBytesCompleted)} / '
                  '${formatBytes(task.progress.currentFileTotalBytes)}',
            ),
          if (task.progress.currentPart > 0 && task.progress.totalParts > 0)
            _detailLine(
              '分块',
              '第 ${task.progress.currentPart} / ${task.progress.totalParts} 块'
                  '${task.progress.currentRange.isEmpty ? '' : ' · ${task.progress.currentRange}'}',
            ),
          if (task.error.isNotEmpty) _detailLine('错误', task.error),
          if (task.remoteOutcome.isNotEmpty)
            _detailLine('远端结果', task.remoteOutcome),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final event in events) _eventLine(event),
          ] else if (task.rawEventCount > 0)
            _detailLine('原始操作', '${task.rawEventCount} 条记录'),
          if (task.physicalTaskIds.isNotEmpty)
            _detailLine('传输', task.physicalTaskIds.join('  ·  ')),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('$label：$value', style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _eventLine(RemoteTaskEvent event) {
    final target = event.targetPath.isNotEmpty
        ? event.targetPath
        : event.sourcePath;
    final folded = event.folded ? '（已合并）' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '#${event.sequence} ${event.kind} $target $folded',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

String remoteTaskSpeedSummary(Iterable<RemoteTask> tasks) {
  final upload = tasks
      .where(
        (task) =>
            task.status == RemoteTaskStatus.running &&
            (task.kind == RemoteTaskKind.upload ||
                task.kind == RemoteTaskKind.write),
      )
      .fold<double>(0, (sum, task) => sum + task.progress.speedBytes);
  final download = tasks
      .where(
        (task) =>
            task.status == RemoteTaskStatus.running &&
            task.kind == RemoteTaskKind.download,
      )
      .fold<double>(0, (sum, task) => sum + task.progress.speedBytes);
  final parts = <String>[
    if (upload > 0) '↑ ${formatBytesPerSecond(upload)}',
    if (download > 0) '↓ ${formatBytesPerSecond(download)}',
  ];
  return parts.isEmpty ? '' : parts.join('  ');
}

String _taskSubtitle(RemoteTask task) {
  if (task.status == RemoteTaskStatus.blocked &&
      task.blockedReason.isNotEmpty) {
    return task.blockedReason;
  }
  if (task.status == RemoteTaskStatus.retryWait &&
      task.nextRetryAt.isNotEmpty) {
    return '将在 ${task.nextRetryAt} 重试';
  }
  if (task.error.isNotEmpty) return task.error;
  if (task.isMountRead) {
    final parts = <String>[
      if (task.mountReadRange.isNotEmpty) '读取范围 ${task.mountReadRange}',
      if (task.progress.totalBytes > 0)
        '${formatBytes(task.progress.bytesCompleted)} / ${formatBytes(task.progress.totalBytes)}',
    ];
    return parts.isEmpty ? '挂载读取' : parts.join(' · ');
  }
  if (task.progress.totalBytes > 0) {
    return '${formatBytes(task.progress.bytesCompleted)} / ${formatBytes(task.progress.totalBytes)}';
  }
  if (task.progress.totalItems > 0) {
    return '${task.progress.itemsCompleted} / ${task.progress.totalItems} 个对象';
  }
  return task.phaseLabel.isNotEmpty ? task.phaseLabel : _statusLabel(task);
}

String _statusLabel(RemoteTask task) => switch (task.status) {
  RemoteTaskStatus.waiting => '等待同步',
  RemoteTaskStatus.blocked => '等待依赖',
  RemoteTaskStatus.running =>
    task.progress.speedBytes > 0
        ? formatBytesPerSecond(task.progress.speedBytes)
        : '执行中',
  RemoteTaskStatus.verifying => '验证远端',
  RemoteTaskStatus.retryWait => '等待重试',
  RemoteTaskStatus.failed => '失败',
  RemoteTaskStatus.conflict => '冲突',
  RemoteTaskStatus.done => '已完成',
  RemoteTaskStatus.cancelRequested => '正在取消',
  RemoteTaskStatus.reconciling => '正在对账',
  RemoteTaskStatus.canceled => '已取消',
};

Color _statusColor(ShadThemeData theme, RemoteTaskStatus status) =>
    switch (status) {
      RemoteTaskStatus.running ||
      RemoteTaskStatus.verifying => theme.colorScheme.primary,
      RemoteTaskStatus.failed ||
      RemoteTaskStatus.conflict => theme.colorScheme.destructive,
      RemoteTaskStatus.done => const Color(0xff15803d),
      _ => theme.colorScheme.mutedForeground,
    };

IconData _kindIcon(RemoteTaskKind kind) => switch (kind) {
  RemoteTaskKind.mkdir => LucideIcons.folderPlus,
  RemoteTaskKind.write || RemoteTaskKind.upload => LucideIcons.upload,
  RemoteTaskKind.download => LucideIcons.download,
  RemoteTaskKind.rename || RemoteTaskKind.move => LucideIcons.moveRight,
  RemoteTaskKind.copy => LucideIcons.copy,
  RemoteTaskKind.delete => LucideIcons.trash2,
  RemoteTaskKind.appUpdate => LucideIcons.refreshCw,
  RemoteTaskKind.unknown => LucideIcons.arrowLeftRight,
};

Color _kindColor(RemoteTaskKind kind) => switch (kind) {
  RemoteTaskKind.write || RemoteTaskKind.upload => const Color(0xff2563eb),
  RemoteTaskKind.download => const Color(0xff0f766e),
  RemoteTaskKind.copy => const Color(0xff7c3aed),
  RemoteTaskKind.rename || RemoteTaskKind.move => const Color(0xffc2410c),
  RemoteTaskKind.delete => const Color(0xffdc2626),
  RemoteTaskKind.appUpdate => const Color(0xff0369a1),
  _ => const Color(0xff64748b),
};

String _kindLabel(RemoteTaskKind kind) => switch (kind) {
  RemoteTaskKind.mkdir => '创建目录',
  RemoteTaskKind.write => '写入文件',
  RemoteTaskKind.upload => '上传',
  RemoteTaskKind.download => '下载',
  RemoteTaskKind.rename => '重命名',
  RemoteTaskKind.copy => '复制',
  RemoteTaskKind.move => '移动',
  RemoteTaskKind.delete => '删除',
  RemoteTaskKind.appUpdate => '应用更新',
  RemoteTaskKind.unknown => '远端操作',
};
