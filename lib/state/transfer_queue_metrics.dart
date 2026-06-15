part of 'transfer_queue.dart';

// Transfer metrics summarize live queue speeds for sidebar and status text.

extension TransferQueueMetrics on TransferQueue {
  String get uploadSpeedText => _speedTextFor(true);
  String get downloadSpeedText => _speedTextFor(false);
  String get objectOperationSpeedText => _speedTextForObjectOps();
  String get sidebarSpeedSummary => _speedSummaryFor(sidebarTaskView);

  String get speedSummary {
    return _speedSummaryFor(_tasks);
  }

  String _speedSummaryFor(Iterable<TransferTask> tasks) {
    final up = _speedTextForTasks(tasks, true);
    final down = _speedTextForTasks(tasks, false);
    final ops = _speedTextForObjectOpsForTasks(tasks);
    if (up.isEmpty && down.isEmpty && ops.isEmpty) {
      final count = tasks
          .where((task) => task.isRunning || task.isPending)
          .length;
      return count > 0 ? '$count 个任务进行中' : '暂无任务';
    }
    final parts = <String>[
      if (up.isNotEmpty) up,
      if (down.isNotEmpty) down,
      if (ops.isNotEmpty) ops,
    ];
    return parts.join('  ');
  }

  String _speedTextFor(bool isUpload) {
    return _speedTextForTasks(_tasks, isUpload);
  }

  String _speedTextForTasks(Iterable<TransferTask> tasks, bool isUpload) {
    final total = tasks
        .where((task) => task.isUpload == isUpload && task.isRunning)
        .fold<double>(0, (sum, task) => sum + task.speedBytes);
    if (total <= 0) return '';
    final prefix = isUpload ? '↑' : '↓';
    return '$prefix ${formatBytesPerSecond(total)}';
  }

  String _speedTextForObjectOps() {
    return _speedTextForObjectOpsForTasks(_tasks);
  }

  String _speedTextForObjectOpsForTasks(Iterable<TransferTask> tasks) {
    final total = tasks
        .where((task) => (task.isCopy || task.isMove) && task.isRunning)
        .fold<double>(0, (sum, task) => sum + task.speedBytes);
    if (total <= 0) return '';
    return '↔ ${formatBytesPerSecond(total)}';
  }
}
