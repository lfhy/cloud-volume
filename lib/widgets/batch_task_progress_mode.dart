// Batch task progress mode centralizes modal copy and icons per operation type.

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum BatchTaskProgressMode {
  upload(
    runningTitle: '正在上传',
    doneTitle: '上传完成',
    runningText: '上传正在进行，可关闭弹框后继续后台上传。',
    batchRunningText: '当前有 {active} 个上传任务正在进行，可关闭弹框后继续后台上传。',
    doneText: '上传任务已完成。',
    batchDoneText: '共处理 {total} 个上传任务，全部已完成。',
    failedDoneText: '共处理 {total} 个上传任务，其中 {failed} 个失败。',
    failedRunningText: '还有 {active} 个任务进行中，{failed} 个任务失败。',
    cancelLabel: '取消上传',
    icon: LucideIcons.upload,
  ),
  download(
    runningTitle: '正在下载',
    doneTitle: '下载完成',
    runningText: '下载正在进行，可关闭弹框后继续后台下载。',
    batchRunningText: '当前有 {active} 个下载任务正在进行，可关闭弹框后继续后台下载。',
    doneText: '下载任务已完成。',
    batchDoneText: '共处理 {total} 个下载任务，全部已完成。',
    failedDoneText: '共处理 {total} 个下载任务，其中 {failed} 个失败。',
    failedRunningText: '还有 {active} 个任务进行中，{failed} 个任务失败。',
    cancelLabel: '取消下载',
    icon: LucideIcons.download,
  ),
  delete(
    runningTitle: '正在删除',
    doneTitle: '删除完成',
    runningText: '删除正在进行，可关闭弹框后继续后台删除。',
    batchRunningText: '当前有 {active} 个删除任务正在进行，可关闭弹框后继续后台删除。',
    doneText: '删除任务已完成。',
    batchDoneText: '共处理 {total} 个删除任务，全部已完成。',
    failedDoneText: '共处理 {total} 个删除任务，其中 {failed} 个失败。',
    failedRunningText: '还有 {active} 个任务进行中，{failed} 个任务失败。',
    cancelLabel: '取消删除',
    icon: LucideIcons.trash2,
  );

  const BatchTaskProgressMode({
    required this.runningTitle,
    required this.doneTitle,
    required this.runningText,
    required this.batchRunningText,
    required this.doneText,
    required this.batchDoneText,
    required this.failedDoneText,
    required this.failedRunningText,
    required this.cancelLabel,
    required this.icon,
  });

  final String runningTitle;
  final String doneTitle;
  final String runningText;
  final String batchRunningText;
  final String doneText;
  final String batchDoneText;
  final String failedDoneText;
  final String failedRunningText;
  final String cancelLabel;
  final IconData icon;

  String description({
    required int totalCount,
    required int activeCount,
    required int failedCount,
    required bool allFinished,
  }) {
    if (allFinished) {
      if (failedCount > 0) {
        return _format(failedDoneText, totalCount, activeCount, failedCount);
      }
      if (totalCount == 1) {
        return doneText;
      }
      return _format(batchDoneText, totalCount, activeCount, failedCount);
    }
    if (failedCount > 0) {
      return _format(failedRunningText, totalCount, activeCount, failedCount);
    }
    if (totalCount == 1) {
      return runningText;
    }
    return _format(batchRunningText, totalCount, activeCount, failedCount);
  }

  String _format(
    String text,
    int totalCount,
    int activeCount,
    int failedCount,
  ) {
    return text
        .replaceAll('{total}', '$totalCount')
        .replaceAll('{active}', '$activeCount')
        .replaceAll('{failed}', '$failedCount');
  }
}
