// Sync-profile cards consume the same RemoteTask projection as the main queue.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

RemoteTask? latestActiveRemoteTaskForProfile(
  Iterable<RemoteTask> tasks,
  String profileId,
) {
  for (final task in tasks) {
    if (task.profileId == profileId && task.status.isActive) return task;
  }
  return null;
}

class FileSyncProfileRemoteTaskLine extends StatelessWidget {
  const FileSyncProfileRemoteTaskLine({super.key, required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final label = switch (task.kind) {
      RemoteTaskKind.mkdir => '同步建目录',
      RemoteTaskKind.write || RemoteTaskKind.upload => '同步上传',
      RemoteTaskKind.download => '同步下载',
      RemoteTaskKind.rename || RemoteTaskKind.move => '同步重命名',
      RemoteTaskKind.delete => '同步删除',
      _ => '同步',
    };
    final path = task.targetPath.isNotEmpty ? task.targetPath : task.sourcePath;
    final progress = task.progress.totalBytes > 0
        ? ' · ${formatBytes(task.progress.bytesCompleted)}/${formatBytes(task.progress.totalBytes)}'
        : '';
    final status = switch (task.status) {
      RemoteTaskStatus.blocked => '等待依赖',
      RemoteTaskStatus.retryWait => '等待重试',
      RemoteTaskStatus.cancelRequested => '正在取消',
      RemoteTaskStatus.reconciling => '正在对账',
      _ => '执行中',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.refreshCw,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前任务：$label · $path$progress',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.foreground,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
