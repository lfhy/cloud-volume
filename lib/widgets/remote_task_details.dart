// Expanded task detail panel: every row renders as a fixed-width label
// column plus a wrapping value, so metadata, localized event records, and
// one-per-line physical transfer IDs all align down the panel. Split from
// remote_task_widgets.dart to keep both files under the size cap.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/remote_task_display.dart';
import 'package:remote_storage/utils/transfer_format.dart';
import 'package:remote_storage/widgets/remote_task_style_helpers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Label column width: fits the longest 4-char label (完整路径/本地路径…)
/// at 11px and left-aligns every value below it.
const double _detailLabelWidth = 60;

class RemoteTaskDetails extends StatelessWidget {
  const RemoteTaskDetails({super.key, required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final events = task.events;
    final accent = remoteTaskKindColor(task.kind);
    return Container(
      margin: const EdgeInsets.only(
        left: remoteTaskContentIndent,
        right: 12,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row(context, '操作', remoteTaskKindLabel(task.kind)),
                    if (task.bucket.trim().isNotEmpty)
                      _row(context, '所属桶', task.bucket),
                    if (task.operationPath.isNotEmpty)
                      _row(context, '完整路径', task.operationPath),
                    if (task.blockedReason.isNotEmpty)
                      _row(
                        context,
                        '依赖',
                        remoteTaskBlockedReasonLabel(task),
                        valueColor: Colors.amber.shade700,
                      ),
                    if (task.mountReadRange.isNotEmpty)
                      _row(context, '读取范围', task.mountReadRange)
                    else if (task.phaseLabel.isNotEmpty)
                      _row(context, '阶段', task.phaseLabel),
                    if (task.sourceTargetSummary.isNotEmpty)
                      _row(context, '路径', task.sourceTargetSummary),
                    if (task.localPath.isNotEmpty)
                      _row(context, '本地路径', task.localPath),
                    if (task.progress.currentKey.isNotEmpty &&
                        task.progress.currentFileTotalBytes > 0)
                      _row(
                        context,
                        '当前文件',
                        '${task.progress.currentKey} '
                            '${formatBytes(task.progress.currentFileBytesCompleted)} / '
                            '${formatBytes(task.progress.currentFileTotalBytes)}',
                      ),
                    if (task.progress.currentPart > 0 &&
                        task.progress.totalParts > 0)
                      _row(
                        context,
                        '分块',
                        '第 ${task.progress.currentPart} / ${task.progress.totalParts} 块'
                            '${task.progress.currentRange.isEmpty ? '' : ' · ${task.progress.currentRange}'}',
                      ),
                    if (task.error.isNotEmpty)
                      _row(
                        context,
                        '错误',
                        task.error,
                        valueColor: theme.colorScheme.destructive,
                      ),
                    if (task.remoteOutcome.isNotEmpty)
                      _row(context, '远端结果', task.remoteOutcome),
                    // Journal events: sequence in the label column, localized
                    // op kind + path as the value (已合并 marks folded chains).
                    if (events.isNotEmpty)
                      for (final event in events) _eventRow(context, event)
                    else if (task.rawEventCount > 0)
                      _row(context, '原始操作', '${task.rawEventCount} 条记录'),
                    // Physical snapshots: one ID per line so long namespace-
                    // qualified IDs never concatenate into one unreadable blob.
                    if (task.physicalTaskIds.isNotEmpty)
                      for (var i = 0; i < task.physicalTaskIds.length; i++)
                        _row(
                          context,
                          i == 0 ? '传输' : '',
                          task.physicalTaskIds[i],
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
    Color? valueBase,
  }) {
    final theme = ShadTheme.of(context);
    final base = valueColor ?? valueBase ?? theme.colorScheme.mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _detailLabelWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: base.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // No maxLines: this panel is the only full-text surface for long
          // provider errors and paths, so values must wrap.
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 11, color: base)),
          ),
        ],
      ),
    );
  }

  Widget _eventRow(BuildContext context, RemoteTaskEvent event) {
    final theme = ShadTheme.of(context);
    final target = event.targetPath.isNotEmpty
        ? event.targetPath
        : event.sourcePath;
    final folded = event.folded ? '（已合并）' : '';
    final value = target.isEmpty
        ? '${remoteTaskEventKindLabel(event.kind)}$folded'
        : '${remoteTaskEventKindLabel(event.kind)} $target$folded';
    return _row(
      context,
      '#${event.sequence}',
      value,
      valueBase: theme.colorScheme.mutedForeground.withValues(alpha: 0.75),
    );
  }
}
