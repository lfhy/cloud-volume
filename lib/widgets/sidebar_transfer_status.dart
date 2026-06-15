// 侧边栏传输状态入口：显示聚合速度、最近任务和快速取消能力。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SidebarTransferStatus extends StatefulWidget {
  const SidebarTransferStatus({
    super.key,
    required this.accent,
    required this.muted,
    required this.onTap,
  });

  final Color accent;
  final Color muted;
  final VoidCallback onTap;

  @override
  State<SidebarTransferStatus> createState() => _SidebarTransferStatusState();
}

class _SidebarTransferStatusState extends State<SidebarTransferStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _hideTimer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    TransferQueue.instance.addListener(_syncAnimation);
    _syncAnimation();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    TransferQueue.instance.removeListener(_syncAnimation);
    _controller.dispose();
    super.dispose();
  }

  void _showHoverCard() {
    _hideTimer?.cancel();
    if (!_hovered) {
      setState(() => _hovered = true);
    }
  }

  void _scheduleHideHoverCard() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() => _hovered = false);
    });
  }

  void _syncAnimation() {
    if (!mounted) {
      return;
    }
    if (TransferQueue.instance.hasSidebarRunning) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final queue = TransferQueue.instance;
    final foreground = queue.hasSidebarRunning ? widget.accent : widget.muted;
    return MouseRegion(
      onEnter: (_) => _showHoverCard(),
      onExit: (_) => _scheduleHideHoverCard(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_hovered) ...[
            Positioned(
              left: 10,
              right: 10,
              bottom: 58,
              child: _TransferHoverCard(theme: theme),
            ),
            const Positioned(
              left: 10,
              right: 10,
              bottom: 50,
              height: 12,
              child: SizedBox(),
            ),
          ],
          AnimatedBuilder(
            animation: queue,
            builder: (context, _) {
              return GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: queue.hasSidebarRunning
                        ? widget.accent.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: queue.hasSidebarRunning
                          ? widget.accent.withValues(alpha: 0.18)
                          : theme.colorScheme.border.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      ScaleTransition(
                        scale: Tween<double>(begin: 1, end: 1.08).animate(
                          CurvedAnimation(
                            parent: _controller,
                            curve: Curves.easeInOut,
                          ),
                        ),
                        child: Opacity(
                          opacity: queue.hasSidebarRunning ? 1 : 0.9,
                          child: Icon(
                            LucideIcons.arrowLeftRight,
                            size: 16,
                            color: foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '对象传输',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: foreground,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              queue.sidebarSpeedSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TransferHoverCard extends StatelessWidget {
  const _TransferHoverCard({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tasks = TransferQueue.instance.recentSidebarTasks();
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: tasks.isEmpty
          ? Text(
              '暂无对象操作任务',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.mutedForeground,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final task in tasks) _TransferHoverRow(task: task),
              ],
            ),
    );
  }
}

class _TransferTaskAction extends StatelessWidget {
  const _TransferTaskAction({
    required this.message,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppTooltip(
      message: message,
      child: ShadIconButton.ghost(
        icon: Icon(icon, size: 13, color: color),
        width: 22,
        height: 22,
        iconSize: 13,
        onPressed: onPressed,
      ),
    );
  }
}

class _TransferHoverRow extends StatelessWidget {
  const _TransferHoverRow({required this.task});

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = _colorFor(task);
    final detail = _detailFor(task);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_iconFor(task), size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _statusLabelFor(task),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: task.status == TransferStatus.failed
                      ? theme.colorScheme.destructive
                      : task.status == TransferStatus.done
                      ? const Color(0xff15803d)
                      : task.status == TransferStatus.canceled
                      ? theme.colorScheme.mutedForeground
                      : theme.colorScheme.primary,
                ),
              ),
              if (task.isCancelable) ...[
                const SizedBox(width: 6),
                _TransferTaskAction(
                  message: '取消任务',
                  icon: LucideIcons.circleX,
                  color: theme.colorScheme.mutedForeground,
                  onPressed: () =>
                      unawaited(TransferQueue.instance.cancelTask(task.id)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _detailFor(TransferTask task) {
    final createdAtLabel = formatTransferCreatedAt(task.createdAt);
    if (task.status == TransferStatus.failed) {
      return _joinHoverParts([
        task.error ?? '${task.typeLabel}失败',
        createdAtLabel,
      ]);
    }
    if (task.status == TransferStatus.canceled) {
      return _joinHoverParts(['${task.typeLabel}已取消', createdAtLabel]);
    }
    if ((task.isCopy || task.isMove) && task.targetPath.isNotEmpty) {
      return _joinHoverParts([
        '${task.typeLabel}到 ${task.targetPath}',
        createdAtLabel,
      ]);
    }
    if (task.totalBytes > 0) {
      return _joinHoverParts([
        '${formatBytes(task.bytesCompleted)} / ${formatBytes(task.totalBytes)}',
        task.progressTargetLabel,
        createdAtLabel,
      ]);
    }
    return _joinHoverParts([task.typeLabel, createdAtLabel]);
  }

  String _statusLabelFor(TransferTask task) {
    return switch (task.status) {
      TransferStatus.pending =>
        task.isUpload ? (task.isUploadWaiting ? '等待上传' : '等待同步') : '等待中',
      TransferStatus.running =>
        task.speedBytes > 0
            ? formatBytesPerSecond(task.speedBytes)
            : '${task.typeLabel}中',
      TransferStatus.done => '完成',
      TransferStatus.failed => '失败',
      TransferStatus.canceled => '已取消',
    };
  }

  IconData _iconFor(TransferTask task) {
    if (task.isUpload) return LucideIcons.upload;
    if (task.isDownload) return LucideIcons.download;
    if (task.isCopy) return LucideIcons.copy;
    if (task.isDelete) return LucideIcons.trash2;
    return LucideIcons.moveRight;
  }

  Color _colorFor(TransferTask task) {
    if (task.isUpload) return const Color(0xff2563eb);
    if (task.isDownload) return const Color(0xff0f766e);
    if (task.isCopy) return const Color(0xff7c3aed);
    if (task.isDelete) return const Color(0xffdc2626);
    return const Color(0xffc2410c);
  }
}

String _joinHoverParts(List<String> parts) {
  return parts.where((part) => part.trim().isNotEmpty).join('  ·  ');
}
