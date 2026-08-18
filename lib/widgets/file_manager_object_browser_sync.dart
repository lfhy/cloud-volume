part of 'file_manager_object_browser.dart';

// The mounted-file badge is derived from the same RemoteTask projection as
// the task page; TransferQueue remains an execution facade only.
extension _FileManagerObjectBrowserSync on FileManagerObjectBrowser {
  Widget? _syncBadge(ObjectInfo object, List<RemoteTask>? tasks) {
    if (!showSyncStatus || _isParentDirectory(object) || _isDeleting(object)) {
      return null;
    }
    return FileSyncStatusBadge(
      state: _syncStateFor(object, tasks ?? const <RemoteTask>[]),
    );
  }

  FileSyncState _syncStateFor(ObjectInfo object, List<RemoteTask> tasks) {
    if (!mountedToDesktop ||
        mountBucketName == null ||
        mountBucketName!.trim().isEmpty) {
      return const FileSyncState.synced();
    }
    final bucket = mountBucketName!.trim();
    final objectKey = object.key.trim();
    final prefix = objectKey.endsWith('/') ? objectKey : '$objectKey/';
    var pending = 0;
    var running = 0;
    for (final task in tasks) {
      if (task.bucket.trim() != bucket || !task.status.isActive) continue;
      if (task.kind != RemoteTaskKind.upload &&
          task.kind != RemoteTaskKind.write) {
        continue;
      }
      final path =
          (task.targetPath.isNotEmpty ? task.targetPath : task.sourcePath)
              .trim();
      if (object.isDir ? !path.startsWith(prefix) : path != objectKey) continue;
      if (task.status == RemoteTaskStatus.running ||
          task.status == RemoteTaskStatus.verifying) {
        running++;
      } else {
        pending++;
      }
    }
    if (pending == 0 && running == 0) return const FileSyncState.synced();
    return FileSyncState.pending(
      pendingCount: pending,
      runningCount: running,
      isDirectory: object.isDir,
    );
  }
}
