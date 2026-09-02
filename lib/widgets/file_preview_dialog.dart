// File preview dialog centralizes inline preview and fallback download actions.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/state/remote_task_store.dart';
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
    this.unavailable = false,
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
  // 当远端对象已不存在时为 true：此时只保留关闭动作，不再提供下载/另存为/外部打开。
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final androidSheet = usesAndroidAppModalSheet;
    final compactAndroidSheet =
        androidSheet && usesCompactAndroidAppModalSheet(context);
    final hasTransfer = transfer != null;
    final previewPane = Container(
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
    );
    final actionBar = _ActionBar(
      transfer: transfer,
      loading: loading,
      unavailable: unavailable,
      onOpenWithSystem: onOpenWithSystem,
      onSaveAs: onSaveAs,
      onDownload: onDownload,
    );
    final body = Column(
      mainAxisSize: androidSheet && !compactAndroidSheet
          ? MainAxisSize.max
          : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (androidSheet && !compactAndroidSheet)
          Expanded(child: previewPane)
        else
          SizedBox(
            // A bounded inner preview avoids nesting an unbounded Markdown
            // scroll view inside the compact sheet's outer scroll view.
            height: compactAndroidSheet ? 160 : 420,
            child: previewPane,
          ),
        const SizedBox(height: 16),
        actionBar,
      ],
    );
    return AppShadDialog(
      title: Text(object.displayName),
      description: Text(previewKindLabel(kind)),
      androidFillHeight: androidSheet,
      scrollable: !androidSheet || compactAndroidSheet,
      child: androidSheet
          ? body
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
              child: body,
            ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.transfer,
    required this.loading,
    required this.unavailable,
    required this.onOpenWithSystem,
    required this.onSaveAs,
    required this.onDownload,
  });

  final FilePreviewTransferState? transfer;
  final bool loading;
  // 远端对象不存在时为 true：隐藏下载相关动作，只保留关闭。
  final bool unavailable;
  final VoidCallback? onOpenWithSystem;
  final VoidCallback onSaveAs;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    if (transfer != null) {
      return AnimatedBuilder(
        animation: RemoteTaskStore.instance,
        builder: (context, _) {
          final task = transfer!.currentTask;
          final running =
              !transfer!.done && (task == null || task.status.isActive);
          // 远端对象已不存在时不再保留取消/后台运行，进度面板已经显示错误，
          // 用户除了关闭弹框（随后会触发目录刷新）没有其它合理动作。
          if (unavailable) {
            return _actionWrap([
              ShadButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ]);
          }
          return _actionWrap([
            if (task?.cancelable ?? false) ...[
              ShadButton.destructive(
                onPressed: () => RemoteTaskStore.instance.cancel(task!.id),
                child: const Text('取消下载'),
              ),
            ],
            ShadButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(running ? '后台运行' : '关闭'),
            ),
          ]);
        },
      );
    }
    return _actionWrap([
      ShadButton.outline(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      // 对象已被远端删除：下载/另存为/外部打开没有意义，直接收起。
      if (!unavailable) ...[
        if (onOpenWithSystem != null) ...[
          ShadButton.outline(
            onPressed: onOpenWithSystem,
            child: const Text('外部应用打开'),
          ),
        ],
        if (!usesAndroidAppModalSheet)
          ShadButton.outline(
            onPressed: loading ? null : onSaveAs,
            child: const Text('另存为'),
          ),
        ShadButton(
          onPressed: loading ? null : onDownload,
          child: const Text('下载'),
        ),
      ],
    ]);
  }

  Widget _actionWrap(List<Widget> actions) {
    if (usesAndroidAppModalSheet) {
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in actions)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: SizedBox(height: 48, child: action),
            ),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: actions,
    );
  }
}

class FilePreviewTransferState {
  const FilePreviewTransferState({
    required this.runningTitle,
    required this.waitingText,
    required this.doneTitle,
    required this.doneText,
    this.taskId,
    this.errorText,
    this.done = false,
  });

  final String runningTitle;
  final String waitingText;
  final String doneTitle;
  final String doneText;
  final String? taskId;
  final String? errorText;
  final bool done;

  RemoteTask? get currentTask {
    final id = taskId;
    if (id == null) return null;
    return RemoteTaskStore.instance.tasks
            .where((candidate) => candidate.id == id)
            .firstOrNull ??
        // Terminal legacy-transfer snapshots intentionally stay out of the
        // task-list source of truth, but preview dialogs still need them.
        RemoteTaskStore.instance.executionTask(id);
  }
}

class _TransferPreviewPane extends StatelessWidget {
  const _TransferPreviewPane({required this.state});

  final FilePreviewTransferState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: RemoteTaskStore.instance,
      builder: (context, _) {
        final task = state.currentTask;
        final errorText = state.errorText ?? _taskError(task);
        final done = state.done || task?.status == RemoteTaskStatus.done;
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

  double? _progressFor(RemoteTask? task, bool done) {
    if (done) {
      return 1;
    }
    if (task == null || task.progress.totalBytes <= 0) {
      return null;
    }
    return task.progress.fraction;
  }

  String? _metaText(RemoteTask? task, bool done) {
    if (task == null) {
      return null;
    }
    if (done) {
      final total = task.progress.totalBytes > 0
          ? task.progress.totalBytes
          : task.progress.bytesCompleted;
      return total > 0 ? formatBytes(total) : null;
    }
    final parts = <String>[];
    if (task.progress.totalBytes > 0) {
      parts.add(
        '${formatBytes(task.progress.bytesCompleted)} / '
        '${formatBytes(task.progress.totalBytes)}',
      );
    } else if (task.progress.bytesCompleted > 0) {
      parts.add(formatBytes(task.progress.bytesCompleted));
    }
    if (task.progress.speedBytes > 0) {
      parts.add(formatBytesPerSecond(task.progress.speedBytes));
    }
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  String? _taskError(RemoteTask? task) {
    if (task == null) {
      return null;
    }
    if (task.status == RemoteTaskStatus.failed) {
      return task.error.isEmpty ? '下载失败' : task.error;
    }
    if (task.status == RemoteTaskStatus.canceled) {
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
