// File preview dialog centralizes inline preview and fallback download actions.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/utils/file_preview_type.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/file_preview_pane.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FilePreviewDialog extends StatelessWidget {
  const FilePreviewDialog({
    super.key,
    required this.object,
    required this.kind,
    required this.source,
    required this.loading,
    required this.errorText,
    this.transfer,
    this.onOpenWithSystem,
    required this.onSaveAs,
    required this.onDownload,
  });

  final ObjectInfo object;
  final FilePreviewKind kind;
  final FilePreviewSource? source;
  final bool loading;
  final String? errorText;
  final FilePreviewTransferState? transfer;
  final VoidCallback? onOpenWithSystem;
  final VoidCallback onSaveAs;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final hasTransfer = transfer != null;
    return ShadDialog(
      title: Text(object.displayName),
      description: Text(previewKindLabel(kind)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 420,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.border),
              ),
              child: hasTransfer
                  ? _TransferPreviewPane(state: transfer!)
                  : FilePreviewPane(
                      kind: kind,
                      source: source,
                      loading: loading,
                      errorText: errorText,
                    ),
            ),
            const SizedBox(height: 16),
            _ActionBar(
              transfer: transfer,
              loading: loading,
              onOpenWithSystem: onOpenWithSystem,
              onSaveAs: onSaveAs,
              onDownload: onDownload,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.transfer,
    required this.loading,
    required this.onOpenWithSystem,
    required this.onSaveAs,
    required this.onDownload,
  });

  final FilePreviewTransferState? transfer;
  final bool loading;
  final VoidCallback? onOpenWithSystem;
  final VoidCallback onSaveAs;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    if (transfer != null) {
      return AnimatedBuilder(
        animation: TransferQueue.instance,
        builder: (context, _) {
          final task = transfer!.currentTask;
          final running = !transfer!.done && (task == null || !task.isFinished);
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (task?.isCancelable ?? false) ...[
                ShadButton.destructive(
                  onPressed: () => TransferQueue.instance.cancelTask(task!.id),
                  child: const Text('取消下载'),
                ),
                const SizedBox(width: 10),
              ],
              ShadButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(running ? '后台运行' : '关闭'),
              ),
            ],
          );
        },
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (onOpenWithSystem != null) ...[
          const SizedBox(width: 10),
          ShadButton.outline(
            onPressed: onOpenWithSystem,
            child: const Text('外部应用打开'),
          ),
        ],
        const SizedBox(width: 10),
        ShadButton.outline(
          onPressed: loading ? null : onSaveAs,
          child: const Text('另存为'),
        ),
        const SizedBox(width: 10),
        ShadButton(
          onPressed: loading ? null : onDownload,
          child: const Text('下载'),
        ),
      ],
    );
  }
}

class FilePreviewTransferState {
  const FilePreviewTransferState({
    required this.runningTitle,
    required this.waitingText,
    required this.doneTitle,
    required this.doneText,
    this.task,
    this.errorText,
    this.done = false,
  });

  final String runningTitle;
  final String waitingText;
  final String doneTitle;
  final String doneText;
  final TransferTask? task;
  final String? errorText;
  final bool done;

  TransferTask? get currentTask {
    final queuedTask = task;
    if (queuedTask == null) {
      return null;
    }
    return TransferQueue.instance.tasks
        .where((candidate) => candidate.id == queuedTask.id)
        .firstOrNull;
  }
}

class _TransferPreviewPane extends StatelessWidget {
  const _TransferPreviewPane({required this.state});

  final FilePreviewTransferState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TransferQueue.instance,
      builder: (context, _) {
        final task = state.currentTask;
        final errorText = state.errorText ?? _taskError(task);
        final done = state.done || task?.status == TransferStatus.done;
        if (errorText != null) {
          return FilePreviewPane.message(
            context,
            Icons.error_outline,
            errorText,
          );
        }
        final progress = _progressFor(task, done);
        return _TransferProgressCard(
          title: done ? state.doneTitle : state.runningTitle,
          description: done ? state.doneText : state.waitingText,
          progress: progress,
          metaText: _metaText(task, done),
          done: done,
        );
      },
    );
  }

  double? _progressFor(TransferTask? task, bool done) {
    if (done) {
      return 1;
    }
    if (task == null || task.totalBytes <= 0) {
      return null;
    }
    return task.progress;
  }

  String? _metaText(TransferTask? task, bool done) {
    if (task == null) {
      return null;
    }
    if (done) {
      final total = task.totalBytes > 0 ? task.totalBytes : task.bytesCompleted;
      return total > 0 ? formatBytes(total) : null;
    }
    final parts = <String>[];
    if (task.totalBytes > 0) {
      parts.add(
        '${formatBytes(task.bytesCompleted)} / '
        '${formatBytes(task.totalBytes)}',
      );
    } else if (task.bytesCompleted > 0) {
      parts.add(formatBytes(task.bytesCompleted));
    }
    if (task.speedBytes > 0) {
      parts.add(formatBytesPerSecond(task.speedBytes));
    }
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  String? _taskError(TransferTask? task) {
    if (task == null) {
      return null;
    }
    if (task.status == TransferStatus.failed) {
      return task.error ?? '下载失败';
    }
    if (task.status == TransferStatus.canceled) {
      return '下载已取消';
    }
    return null;
  }
}

class _TransferProgressCard extends StatelessWidget {
  const _TransferProgressCard({
    required this.title,
    required this.description,
    required this.progress,
    required this.metaText,
    required this.done,
  });

  final String title;
  final String description;
  final double? progress;
  final String? metaText;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done)
                Icon(
                  LucideIcons.circleCheckBig,
                  size: 42,
                  color: const Color(0xff15803d),
                )
              else
                const SizedBox(
                  width: 42,
                  height: 42,
                  child: AppLoadingIndicator(strokeWidth: 3),
                ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.foreground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.background,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
              if (metaText != null) ...[
                const SizedBox(height: 10),
                Text(
                  metaText!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
