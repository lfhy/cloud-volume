// Pure label/color/summary lookups shared by task rows, the transfers page,
// and the sidebar status entry. Kept free of widget code so both the unified
// task list and compact hover rows resolve identical task presentation.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/remote_task_display.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Aggregate live upload/download speed across running tasks ("↑ 1.2 MB/s ↓ ...").
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

/// One-line progress/error summary under the task title; most specific first.
String remoteTaskSubtitle(RemoteTask task) {
  if (task.status == RemoteTaskStatus.blocked &&
      task.blockedReason.isNotEmpty) {
    return remoteTaskBlockedReasonLabel(task);
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
  return task.phaseLabel.isNotEmpty ? task.phaseLabel : remoteTaskStatusLabel(task);
}

/// Metadata blocked reasons are fixed English wire strings; map the known
/// one to a localized label and pass anything else through unchanged.
String remoteTaskBlockedReasonLabel(RemoteTask task) {
  final reason = task.blockedReason.trim();
  if (reason.toLowerCase() == 'waiting for journal dependencies') {
    return '等待前置操作完成';
  }
  return reason;
}

/// Row title: the entry name only (last non-empty path segment) so the row
/// reads like a file listing; the full path/op/bucket live in the detail
/// panel. Falls back to the kind label when the task has no name.
String remoteTaskEntryName(RemoteTask task) {
  final path = task.operationPath;
  final trimmed = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  final slash = trimmed.lastIndexOf('/');
  final name = (slash >= 0 ? trimmed.substring(slash + 1) : trimmed).trim();
  return name.isEmpty ? remoteTaskKindLabel(task.kind) : name;
}

String remoteTaskStatusLabel(RemoteTask task) => switch (task.status) {
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

Color remoteTaskStatusColor(ShadThemeData theme, RemoteTaskStatus status) =>
    switch (status) {
      RemoteTaskStatus.running ||
      RemoteTaskStatus.verifying => theme.colorScheme.primary,
      RemoteTaskStatus.failed ||
      RemoteTaskStatus.conflict => theme.colorScheme.destructive,
      RemoteTaskStatus.done => const Color(0xff15803d),
      _ => theme.colorScheme.mutedForeground,
    };

IconData remoteTaskKindIcon(RemoteTaskKind kind) => switch (kind) {
  RemoteTaskKind.mkdir => LucideIcons.folderPlus,
  RemoteTaskKind.write || RemoteTaskKind.upload => LucideIcons.upload,
  RemoteTaskKind.download => LucideIcons.download,
  RemoteTaskKind.rename || RemoteTaskKind.move => LucideIcons.moveRight,
  RemoteTaskKind.copy => LucideIcons.copy,
  RemoteTaskKind.delete => LucideIcons.trash2,
  RemoteTaskKind.appUpdate => LucideIcons.refreshCw,
  RemoteTaskKind.unknown => LucideIcons.arrowLeftRight,
};

Color remoteTaskKindColor(RemoteTaskKind kind) => switch (kind) {
  RemoteTaskKind.write || RemoteTaskKind.upload => const Color(0xff2563eb),
  RemoteTaskKind.download => const Color(0xff0f766e),
  RemoteTaskKind.copy => const Color(0xff7c3aed),
  RemoteTaskKind.rename || RemoteTaskKind.move => const Color(0xffc2410c),
  RemoteTaskKind.delete => const Color(0xffdc2626),
  RemoteTaskKind.appUpdate => const Color(0xff0369a1),
  _ => const Color(0xff64748b),
};

String remoteTaskKindLabel(RemoteTaskKind kind) => switch (kind) {
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
