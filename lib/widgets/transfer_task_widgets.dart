// Transfer task widgets keep task rows and batch actions consistent with the file manager list style.

import 'package:flutter/material.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:remote_storage/widgets/page_header_actions.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class TransferStatusBadge extends StatelessWidget {
  const TransferStatusBadge({
    super.key,
    required this.task,
    this.showSpeed = true,
  });

  final TransferTask task;
  final bool showSpeed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final text = switch (task.status) {
      TransferStatus.pending =>
        task.statusDetail == 'selecting_path'
            ? '选择路径'
            : task.isAppUpdate
            ? '等待更新'
            : task.isUpload
            ? (task.isUploadWaiting ? '等待上传' : '等待同步')
            : '等待中',
      TransferStatus.running =>
        task.statusDetail == 'scanning'
            ? '扫描中'
            : showSpeed && task.speedBytes > 0
            ? formatBytesPerSecond(task.speedBytes)
            : '${task.typeLabel}中',
      TransferStatus.done => '已完成',
      TransferStatus.failed => '失败',
      TransferStatus.canceled => '已取消',
    };
    final color = switch (task.status) {
      TransferStatus.pending => theme.colorScheme.mutedForeground,
      TransferStatus.running => theme.colorScheme.primary,
      TransferStatus.done => const Color(0xff15803d),
      TransferStatus.failed => theme.colorScheme.destructive,
      TransferStatus.canceled => theme.colorScheme.mutedForeground,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class TransferTaskRow extends StatefulWidget {
  const TransferTaskRow({
    super.key,
    required this.task,
    required this.subtitle,
    required this.selected,
    required this.onToggleSelected,
    this.showDivider = true,
    this.onCancelPressed,
    this.onStartNowPressed,
    this.onRetryPressed,
    this.onRemovePressed,
  });

  final TransferTask task;
  final String subtitle;
  final bool selected;
  final bool showDivider;
  final VoidCallback onToggleSelected;
  final VoidCallback? onCancelPressed;
  final VoidCallback? onStartNowPressed;
  final VoidCallback? onRetryPressed;
  final VoidCallback? onRemovePressed;

  @override
  State<TransferTaskRow> createState() => _TransferTaskRowState();
}

class _TransferTaskRowState extends State<TransferTaskRow> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accentColor = _colorFor(widget.task);
    final interactionColors = ListInteractionColors.fromTheme(theme);
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.55);
    final backgroundColor = interactionColors.rowBackground(
      selected: widget.selected,
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
        onTap: widget.onToggleSelected,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
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
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  _iconFor(widget.task),
                  size: 18,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.task.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onCancelPressed != null)
                    AppTooltip(
                      message: '取消任务',
                      child: ShadIconButton.ghost(
                        icon: Icon(
                          LucideIcons.circleX,
                          color: theme.colorScheme.mutedForeground,
                        ),
                        width: 28,
                        height: 28,
                        iconSize: 16,
                        onPressed: widget.onCancelPressed,
                      ),
                    ),
                  if (widget.onStartNowPressed != null)
                    AppTooltip(
                      message: '立即同步',
                      child: ShadIconButton.ghost(
                        icon: Icon(
                          LucideIcons.play,
                          color: theme.colorScheme.primary,
                        ),
                        width: 28,
                        height: 28,
                        iconSize: 16,
                        onPressed: widget.onStartNowPressed,
                      ),
                    ),
                  if (widget.onRetryPressed != null)
                    AppTooltip(
                      message: '重试任务',
                      child: ShadIconButton.ghost(
                        icon: Icon(
                          LucideIcons.refreshCw,
                          color: theme.colorScheme.primary,
                        ),
                        width: 28,
                        height: 28,
                        iconSize: 16,
                        onPressed: widget.onRetryPressed,
                      ),
                    ),
                  if (widget.onRemovePressed != null)
                    AppTooltip(
                      message: '从记录移除',
                      child: ShadIconButton.ghost(
                        icon: Icon(
                          LucideIcons.trash2,
                          color: theme.colorScheme.mutedForeground,
                        ),
                        width: 28,
                        height: 28,
                        iconSize: 16,
                        onPressed: widget.onRemovePressed,
                      ),
                    ),
                  const SizedBox(width: 8),
                  TransferStatusBadge(task: widget.task),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TransferTaskSelectionActions extends StatelessWidget {
  const TransferTaskSelectionActions({
    super.key,
    required this.selectedCount,
    required this.selectedVisibleCount,
    required this.startableCount,
    required this.cancelableCount,
    required this.removableCount,
    required this.finishedCount,
    required this.runningBatchAction,
    required this.onStartSelected,
    required this.onCancelSelected,
    required this.onRemoveSelected,
    required this.onClearFinished,
  });

  final int selectedCount;
  final int selectedVisibleCount;
  final int startableCount;
  final int cancelableCount;
  final int removableCount;
  final int finishedCount;
  final bool runningBatchAction;
  final VoidCallback onStartSelected;
  final VoidCallback onCancelSelected;
  final VoidCallback onRemoveSelected;
  final VoidCallback onClearFinished;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final hasSelection = selectedCount > 0;
    return PageHeaderActions(
      // 主操作：选中徽标 + 批量开始 + 批量取消 + 移除记录，统一 outline 风格。
      primary: [
        if (hasSelection)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _selectionSummary(
                selectedCount: selectedCount,
                selectedVisibleCount: selectedVisibleCount,
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (runningBatchAction)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '处理中...',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
        if (hasSelection)
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: runningBatchAction || startableCount == 0
                ? null
                : onStartSelected,
            child: Text(
              startableCount > 0 ? '批量开始 $startableCount' : '批量开始',
            ),
          ),
        if (hasSelection)
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: runningBatchAction || cancelableCount == 0
                ? null
                : onCancelSelected,
            child: Text(
              cancelableCount > 0 ? '批量取消 $cancelableCount' : '批量取消',
            ),
          ),
        if (hasSelection)
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: runningBatchAction || removableCount == 0
                ? null
                : onRemoveSelected,
            child: Text(
              removableCount > 0 ? '移除记录 $removableCount' : '移除记录',
            ),
          ),
      ],
      // 次操作：宽度不足时收进「…」菜单。
      secondary: [
        // 仅在非多选模式下显示「清空已完成」。
        if (!hasSelection && finishedCount > 0)
          SecondaryAction(
            label: '清空已完成',
            onPressed: runningBatchAction ? null : onClearFinished,
            enabled: !runningBatchAction,
            builder: (_) => ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: runningBatchAction ? null : onClearFinished,
              child: const Text('清空已完成'),
            ),
          ),
      ],
    );
  }
}

class TransferTaskListHeader extends StatelessWidget {
  const TransferTaskListHeader({
    super.key,
    required this.totalCount,
    required this.speedSummary,
    required this.allVisibleSelected,
    required this.partiallySelected,
    required this.onToggleVisibleSelection,
  });

  final int totalCount;
  final String speedSummary;
  final bool allVisibleSelected;
  final bool partiallySelected;
  final VoidCallback onToggleVisibleSelection;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.7);
    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.mutedForeground,
      letterSpacing: 0.2,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 0.6)),
      ),
      child: Row(
        children: [
          ListSelectionControl(
            selected: allVisibleSelected,
            partiallySelected: partiallySelected,
            onTap: onToggleVisibleSelection,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              allVisibleSelected ? '取消全选当前结果' : '全选当前结果',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.foreground,
              ),
            ),
          ),
          Text('共 $totalCount 项', style: labelStyle),
          const SizedBox(width: 16),
          Text(speedSummary, style: labelStyle),
        ],
      ),
    );
  }
}

String _selectionSummary({
  required int selectedCount,
  required int selectedVisibleCount,
}) {
  if (selectedVisibleCount == selectedCount) {
    return '已选 $selectedCount 项';
  }
  return '已选 $selectedCount 项，当前筛选中 $selectedVisibleCount 项';
}

IconData _iconFor(TransferTask task) {
  if (task.isAppUpdate) return LucideIcons.refreshCw;
  if (task.isUpload) return LucideIcons.upload;
  if (task.isDownload) return LucideIcons.download;
  if (task.isCopy) return LucideIcons.copy;
  if (task.isDelete) return LucideIcons.trash2;
  return LucideIcons.moveRight;
}

Color _colorFor(TransferTask task) {
  if (task.isAppUpdate) return const Color(0xff0369a1);
  if (task.isUpload) return const Color(0xff2563eb);
  if (task.isDownload) return const Color(0xff0f766e);
  if (task.isCopy) return const Color(0xff7c3aed);
  if (task.isDelete) return const Color(0xffdc2626);
  return const Color(0xffc2410c);
}
