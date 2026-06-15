part of 'transfer_queue.dart';

// Foreground task tracking lets dialogs mark ownership while the sidebar still
// reflects the full live queue instead of looking idle during modal transfers.
extension TransferQueueForeground on TransferQueue {
  Iterable<TransferTask> get sidebarTaskView => _tasks;

  bool get hasSidebarRunning =>
      sidebarTaskView.any((task) => task.isRunning || task.isPending);

  int get sidebarRunningCount =>
      sidebarTaskView.where((task) => task.isRunning || task.isPending).length;

  List<TransferTask> recentSidebarTasks({int limit = 6}) {
    if (limit <= 0 || _tasks.isEmpty) {
      return const <TransferTask>[];
    }
    return sidebarTaskView.take(limit).toList(growable: false);
  }

  void markTasksForeground(Iterable<String> ids) {
    final before = _foregroundTaskIds.length;
    _foregroundTaskIds.addAll(ids.where((id) => _tasksById.containsKey(id)));
    if (_foregroundTaskIds.length != before) {
      _scheduleNotifyListeners();
    }
  }

  void clearTasksForeground(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      changed = _foregroundTaskIds.remove(id) || changed;
    }
    if (changed) {
      _scheduleNotifyListeners();
    }
  }
}
