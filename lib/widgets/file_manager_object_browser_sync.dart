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
    final expectedProfile = profileId?.trim() ?? '';
    var pending = 0;
    var running = 0;
    for (final task in tasks) {
      if (task.bucket.trim() != bucket || !task.status.isActive) continue;
      if (expectedProfile.isNotEmpty &&
          task.profileId.trim() != expectedProfile) {
        continue;
      }
      if (!_taskCanChangeObject(task) || !_taskMatchesObject(task, object)) {
        continue;
      }
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

  bool _taskCanChangeObject(RemoteTask task) {
    return switch (task.kind) {
      RemoteTaskKind.mkdir ||
      RemoteTaskKind.write ||
      RemoteTaskKind.upload ||
      RemoteTaskKind.rename ||
      RemoteTaskKind.copy ||
      RemoteTaskKind.move ||
      RemoteTaskKind.delete => true,
      RemoteTaskKind.download ||
      RemoteTaskKind.appUpdate ||
      RemoteTaskKind.unknown => false,
    };
  }

  bool _taskMatchesObject(RemoteTask task, ObjectInfo object) {
    final objectPath = _normalizedTaskPath(object.key);
    if (objectPath.isEmpty) return false;
    final paths = <String>{task.sourcePath, task.targetPath, task.displayPath};
    return paths.any((path) {
      final taskPath = _normalizedTaskPath(path);
      if (taskPath.isEmpty) return false;
      return object.isDir
          ? taskPath == objectPath || taskPath.startsWith('$objectPath/')
          : taskPath == objectPath;
    });
  }

  String _normalizedTaskPath(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^/+'), '')
      .replaceFirst(RegExp(r'/+$'), '');
}
