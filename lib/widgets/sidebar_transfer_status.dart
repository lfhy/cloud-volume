// 侧边栏传输状态入口：显示聚合速度、最近任务和快速取消能力。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/remote_task_display.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:remote_storage/widgets/remote_task_widgets.dart';
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
    RemoteTaskStore.instance.addListener(_syncAnimation);
    _syncAnimation();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    RemoteTaskStore.instance.removeListener(_syncAnimation);
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
    if (_hasRunning) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = _hasRunning ? widget.accent : widget.muted;
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
            animation: Listenable.merge([RemoteTaskStore.instance]),
            builder: (context, _) {
              final running = _hasRunning;
              return GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: running
                        ? widget.accent.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: running
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
                          opacity: running ? 1 : 0.9,
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
                              '远端操作',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: foreground,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _speedSummary,
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

extension on _SidebarTransferStatusState {
  bool get _hasRunning => RemoteTaskStore.instance.hasActive;

  String get _speedSummary =>
      remoteTaskSpeedSummary(RemoteTaskStore.instance.tasks).isEmpty
      ? (_hasRunning ? '同步中' : '暂无任务')
      : remoteTaskSpeedSummary(RemoteTaskStore.instance.tasks);
}

class _TransferHoverCard extends StatelessWidget {
  const _TransferHoverCard({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final remoteTasks = RemoteTaskStore.instance.tasks.take(6).toList();
    final isEmpty = remoteTasks.isEmpty;
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
      child: isEmpty
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
                for (final task in remoteTasks) _RemoteHoverRow(task: task),
              ],
            ),
    );
  }
}

class _RemoteHoverRow extends StatelessWidget {
  const _RemoteHoverRow({required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final path = task.operationPath;
    final active = task.status.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            _remoteIcon(task.kind),
            size: 15,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path.isEmpty ? task.name : path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (task.cancelable) ...[
            const SizedBox(width: 6),
            _TransferTaskAction(
              message: '取消任务',
              icon: LucideIcons.circleX,
              color: theme.colorScheme.mutedForeground,
              onPressed: () =>
                  unawaited(RemoteTaskStore.instance.cancel(task.id)),
            ),
          ],
          const SizedBox(width: 6),
          Text(
            active ? '进行中' : _remoteStatus(task.status),
            style: TextStyle(
              fontSize: 10.5,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _remoteIcon(RemoteTaskKind kind) => switch (kind) {
  RemoteTaskKind.mkdir => LucideIcons.folderPlus,
  RemoteTaskKind.write || RemoteTaskKind.upload => LucideIcons.upload,
  RemoteTaskKind.download => LucideIcons.download,
  RemoteTaskKind.rename || RemoteTaskKind.move => LucideIcons.moveRight,
  RemoteTaskKind.copy => LucideIcons.copy,
  RemoteTaskKind.delete => LucideIcons.trash2,
  RemoteTaskKind.appUpdate => LucideIcons.refreshCw,
  RemoteTaskKind.unknown => LucideIcons.arrowLeftRight,
};

String _remoteStatus(RemoteTaskStatus status) => switch (status) {
  RemoteTaskStatus.failed || RemoteTaskStatus.conflict => '失败',
  RemoteTaskStatus.done => '完成',
  RemoteTaskStatus.canceled => '已取消',
  _ => '等待中',
};

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
