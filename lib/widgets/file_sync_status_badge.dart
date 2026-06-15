// 文件同步状态徽标：复用在列表列和网格项底部，集中管理视觉文案。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileSyncState {
  const FileSyncState({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  const FileSyncState.synced()
    : this(
        label: '已同步',
        subtitle: '远端已同步',
        icon: LucideIcons.badgeCheck,
        color: const Color(0xff15803d),
      );

  factory FileSyncState.pending({
    required int pendingCount,
    required int runningCount,
    required bool isDirectory,
  }) {
    if (runningCount > 0 && pendingCount > 0) {
      return FileSyncState(
        label: '同步中',
        subtitle: isDirectory
            ? '同步中 $runningCount 项，等待 $pendingCount 项'
            : '同步中，后续还有 $pendingCount 次写回等待',
        icon: LucideIcons.refreshCw,
        color: const Color(0xff2563eb),
      );
    }
    if (runningCount > 0) {
      return FileSyncState(
        label: '同步中',
        subtitle: isDirectory ? '同步中 $runningCount 项' : '正在同步到远端',
        icon: LucideIcons.refreshCw,
        color: const Color(0xff2563eb),
      );
    }
    return FileSyncState(
      label: pendingCount > 1 && isDirectory ? '等待 $pendingCount' : '等待同步',
      subtitle: isDirectory ? '等待同步 $pendingCount 项' : '等待同步到远端',
      icon: LucideIcons.clock3,
      color: const Color(0xffb45309),
    );
  }

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class FileSyncStatusBadge extends StatelessWidget {
  const FileSyncStatusBadge({super.key, required this.state});

  final FileSyncState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: state.color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(state.icon, size: 11.5, color: state.color),
          const SizedBox(width: 4),
          Text(
            state.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: state.color,
            ),
          ),
        ],
      ),
    );
  }
}
