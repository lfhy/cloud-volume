part of 'transfer_queue.dart';

// Directory child helpers keep parent cancellation from leaving file rows stuck.
extension TransferQueueDirectoryChildren on TransferQueue {
  Future<void> _cancelDirectoryChildTasks(String parentTaskId) async {
    final childPrefix = '$parentTaskId:file:';
    final childIds = _tasks
        .where((task) => task.id.startsWith(childPrefix) && !task.isFinished)
        .map((task) => task.id)
        .toList(growable: false);
    for (final childId in childIds) {
      final child = _taskById(childId);
      if (child == null || child.isFinished) {
        continue;
      }
      child.status = TransferStatus.canceled;
      child.speedBytes = 0;
      child.error = null;
      _cancelRequestedIds.add(childId);
      if (_api != null) {
        await _api!.cancelTransfer(childId);
      }
    }
    if (childIds.isNotEmpty) {
      scheduleTransferQueuePersist(this);
      _scheduleNotifyListeners();
    }
  }
}
