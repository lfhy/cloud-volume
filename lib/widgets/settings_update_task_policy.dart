// Update-task policy keeps irreversible installer capability decisions out of
// the settings widget so the same rules can be exercised without rendering UI.

import 'package:remote_storage/models/remote_task.dart';

RemoteTask? findAppUpdateTask(Iterable<RemoteTask> tasks, String? taskId) {
  final rawId = taskId?.trim() ?? '';
  if (rawId.isEmpty) return null;
  final normalized = rawId.startsWith('transfer:') ? rawId : 'transfer:$rawId';
  for (final task in tasks) {
    if (task.id == normalized) return task;
  }
  return null;
}

/// A missing remote snapshot is not cancelable once a task has been created.
bool canCancelAppUpdate({
  required bool installing,
  required String? taskId,
  required Iterable<RemoteTask> tasks,
}) {
  if (!installing) return false;
  if (taskId == null || taskId.trim().isEmpty) {
    // This is the pre-download quiet-period wait; canceling only stops the
    // local wait and does not claim that an installer was interrupted.
    return true;
  }
  final task = findAppUpdateTask(tasks, taskId);
  return task != null &&
      task.status.isActive &&
      task.cancelable &&
      task.phaseDetail != 'installing';
}
