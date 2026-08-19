// Batch task progress dialog keeps multi-item operations visible while they run.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/remote_task_display.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/batch_task_progress_mode.dart';
import 'package:remote_storage/widgets/remote_task_widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class BatchTaskProgressDialog extends StatelessWidget {
  const BatchTaskProgressDialog({
    super.key,
    required this.taskIds,
    required this.currentPathLabel,
    required this.onRunInBackground,
    required this.onClose,
    this.mode,
  });

  final List<String> taskIds;
  final String currentPathLabel;
  final VoidCallback onRunInBackground;
  final VoidCallback onClose;
  final BatchTaskProgressMode? mode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: RemoteTaskStore.instance,
      builder: (context, _) {
        final ids = taskIds.map(_remoteTaskID).toSet();
        final tasksById = <String, RemoteTask>{};
        for (final task in RemoteTaskStore.instance.tasks) {
          if (ids.contains(task.id)) tasksById[task.id] = task;
        }
        for (final id in ids) {
          final task = RemoteTaskStore.instance.executionTask(id);
          if (task != null) tasksById[id] = task;
        }
        final tasks = tasksById.values.toList(growable: false);
        final finishedCount = tasks
            .where((task) => !task.status.isActive)
            .length;
        final failedCount = tasks
            .where((task) => task.status == RemoteTaskStatus.failed)
            .length;
        final activeCount = tasks.length - finishedCount;
        final allFinished = tasks.isNotEmpty && activeCount == 0;
        final totalBytes = tasks.fold<int>(
          0,
          (sum, task) => task.progress.totalBytes > 0
              ? sum + task.progress.totalBytes
              : sum,
        );
        final completedBytes = tasks.fold<int>(
          0,
          (sum, task) => sum + task.progress.bytesCompleted,
        );
        final totalSpeed = tasks.fold<double>(
          0,
          (sum, task) => sum + task.progress.speedBytes,
        );
        final totalItems = tasks.fold<int>(
          0,
          (sum, task) => sum + task.progress.totalItems,
        );
        final completedItems = tasks.fold<int>(
          0,
          (sum, task) => sum + task.progress.itemsCompleted,
        );
        final progress = totalItems > 0
            ? (completedItems / totalItems).clamp(0.0, 1.0)
            : totalBytes > 0
            ? (completedBytes / totalBytes).clamp(0.0, 1.0)
            : allFinished
            ? 1.0
            : null;
        final resolvedMode = mode ?? _modeForTasks(tasks);

        // Enter confirms: close when finished, run-in-background while active.
        return Focus(
          autofocus: true,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): allFinished
                  ? onClose
                  : onRunInBackground,
            },
            child: ShadDialog(
              title: Text(
                allFinished
                    ? resolvedMode.doneTitle
                    : resolvedMode.runningTitle,
              ),
              description: Text(
                resolvedMode.description(
                  totalCount: tasks.length,
                  activeCount: activeCount,
                  failedCount: failedCount,
                  allFinished: allFinished,
                ),
              ),
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SummaryCard(
                      currentPathLabel: currentPathLabel,
                      totalCount: tasks.length,
                      activeCount: activeCount,
                      failedCount: failedCount,
                      progress: progress,
                      completedBytes: completedBytes,
                      totalBytes: totalBytes,
                      completedItems: completedItems,
                      totalItems: totalItems,
                      totalSpeed: totalSpeed,
                      allFinished: allFinished,
                      mode: resolvedMode,
                    ),
                    const SizedBox(height: 14),
                    if (tasks.isNotEmpty)
                      _TaskList(tasks: tasks, mode: resolvedMode),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (allFinished)
                          ShadButton.outline(
                            onPressed: onClose,
                            child: const Text('关闭'),
                          )
                        else ...[
                          ShadButton.destructive(
                            onPressed: () => _cancelActiveTasks(tasks),
                            child: Text(resolvedMode.cancelLabel),
                          ),
                          const SizedBox(width: 10),
                          ShadButton(
                            onPressed: onRunInBackground,
                            child: const Text('后台运行'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _cancelActiveTasks(List<RemoteTask> tasks) {
    for (final task in tasks.where((task) => task.cancelable)) {
      unawaited(RemoteTaskStore.instance.cancel(task.id));
    }
  }

  BatchTaskProgressMode _modeForTasks(List<RemoteTask> tasks) {
    if (tasks.isNotEmpty &&
        tasks.every((task) => task.kind == RemoteTaskKind.delete)) {
      return BatchTaskProgressMode.delete;
    }
    return BatchTaskProgressMode.upload;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.currentPathLabel,
    required this.totalCount,
    required this.activeCount,
    required this.failedCount,
    required this.progress,
    required this.completedBytes,
    required this.totalBytes,
    required this.completedItems,
    required this.totalItems,
    required this.totalSpeed,
    required this.allFinished,
    required this.mode,
  });

  final String currentPathLabel;
  final int totalCount;
  final int activeCount;
  final int failedCount;
  final double? progress;
  final int completedBytes;
  final int totalBytes;
  final int completedItems;
  final int totalItems;
  final double totalSpeed;
  final bool allFinished;
  final BatchTaskProgressMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (allFinished)
                Icon(
                  LucideIcons.circleCheckBig,
                  size: 18,
                  color: const Color(0xff15803d),
                )
              else
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: AppLoadingIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  currentPathLabel.isEmpty ? '当前目录' : currentPathLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: theme.colorScheme.background,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              if (totalCount > 1) _metaChip(theme, '$totalCount 个任务'),
              if (totalCount > 1 && !allFinished)
                _metaChip(theme, '进行中 $activeCount'),
              if (failedCount > 0)
                _metaChip(
                  theme,
                  '失败 $failedCount',
                  color: theme.colorScheme.destructive,
                ),
              if (totalBytes > 0)
                _metaChip(theme, _bytesText(completedBytes, totalBytes)),
              if (totalItems > 0)
                _metaChip(
                  theme,
                  '${completedItems > totalItems ? totalItems : completedItems} / $totalItems 个对象',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaChip(ShadThemeData theme, String text, {Color? color}) {
    final foreground = color ?? theme.colorScheme.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }

  String _bytesText(int completedBytes, int totalBytes) {
    final text = '${formatBytes(completedBytes)} / ${formatBytes(totalBytes)}';
    if (!allFinished && totalSpeed > 0) {
      return '$text  ·  ${formatBytesPerSecond(totalSpeed)}';
    }
    return text;
  }
}

String _remoteTaskID(String id) {
  if (id.startsWith('transfer:') || id.startsWith('sync:')) return id;
  return 'transfer:$id';
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks, required this.mode});

  final List<RemoteTask> tasks;
  final BatchTaskProgressMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: tasks.length,
        separatorBuilder: (_, index) => Divider(
          height: 1,
          thickness: 0.6,
          color: theme.colorScheme.border.withValues(alpha: 0.65),
        ),
        itemBuilder: (context, index) {
          final task = tasks[index];
          final subtitle = _subtitleFor(task);
          final errorText = _errorTextFor(task);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(mode.icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                      if (errorText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          errorText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.25,
                            color: theme.colorScheme.destructive,
                          ),
                        ),
                      ],
                      if (task.progress.totalBytes > 0) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: task.progress.fraction,
                            minHeight: 5,
                            backgroundColor: theme.colorScheme.muted,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                RemoteTaskStatusBadge(task: task),
                if (task.cancelable) ...[
                  const SizedBox(width: 8),
                  ShadIconButton.ghost(
                    icon: Icon(
                      LucideIcons.circleX,
                      color: theme.colorScheme.destructive,
                    ),
                    width: 30,
                    height: 30,
                    iconSize: 16,
                    onPressed: () =>
                        unawaited(RemoteTaskStore.instance.cancel(task.id)),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _subtitleFor(RemoteTask task) {
    final parts = <String>[
      if (task.operationPath.isNotEmpty) task.operationPath,
      if (task.localPath.isNotEmpty) '本地：${task.localPath}',
    ];
    if (task.phaseDetail == 'selecting_path') {
      parts.add('等待选择保存位置');
    }
    final isDeleteSweep =
        task.kind == RemoteTaskKind.delete && task.phaseDetail == 'deleting';
    if (isDeleteSweep) {
      parts.add('正在删除源对象');
    }
    if (task.progress.totalItems > 0) {
      // Multi-phase sweeps restart the item bar per phase, so completed can
      // briefly exceed the running total; clamp to avoid "2N / N" labels.
      final completed = task.progress.itemsCompleted > task.progress.totalItems
          ? task.progress.totalItems
          : task.progress.itemsCompleted;
      parts.add('$completed / ${task.progress.totalItems} 个对象');
    } else if (task.phaseDetail == 'scanning') {
      parts.add('正在扫描文件');
    }
    if (task.progress.totalBytes > 0) {
      parts.add(formatBytes(task.progress.totalBytes));
    }
    if (task.progress.currentKey.isNotEmpty) {
      final currentBytes = task.progress.totalBytes > 0
          ? '${formatBytes(task.progress.bytesCompleted)} / ${formatBytes(task.progress.totalBytes)}'
          : '';
      parts.add(
        currentBytes.isEmpty
            ? '当前文件 ${task.progress.currentKey}'
            : '当前文件 ${task.progress.currentKey}  $currentBytes',
      );
    } else if (task.mountReadRange.isNotEmpty) {
      parts.add('读取范围 ${task.mountReadRange}');
    } else if (task.targetPath.isNotEmpty) {
      parts.add(task.targetPath);
    }
    return parts.join('  ·  ');
  }

  String _errorTextFor(RemoteTask task) {
    if (task.status != RemoteTaskStatus.failed) {
      return '';
    }
    final raw = task.error.trim();
    if (raw.isEmpty) {
      return '失败原因未返回，请查看 bridge 日志。';
    }
    return describeBridgeError(raw);
  }
}
