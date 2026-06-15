part of 'transfer_queue.dart';

// Mounted writeback sync helpers project transfer state back into file rows.

extension TransferQueueSyncState on TransferQueue {
  FileSyncState syncStateForObject({
    required String bucket,
    required String objectKey,
    required bool isDirectory,
  }) {
    final cleanBucket = bucket.trim();
    if (cleanBucket.isEmpty) {
      return const FileSyncState.synced();
    }

    var pending = 0;
    var running = 0;
    final dirPrefix = isDirectory ? _syncDirPrefix(objectKey) : '';
    for (final entry in _mountWritebackCounts.entries) {
      final bucketAndPath = entry.key;
      final separator = bucketAndPath.indexOf('\n');
      if (separator <= 0) {
        continue;
      }
      if (bucketAndPath.substring(0, separator) != cleanBucket) {
        continue;
      }
      final taskPath = bucketAndPath.substring(separator + 1);
      final matches = isDirectory
          ? taskPath.startsWith(dirPrefix)
          : taskPath == objectKey;
      if (!matches) {
        continue;
      }
      pending += entry.value.pending;
      running += entry.value.running;
    }

    if (running > 0 || pending > 0) {
      return FileSyncState.pending(
        pendingCount: pending,
        runningCount: running,
        isDirectory: isDirectory,
      );
    }
    return const FileSyncState.synced();
  }

  String _syncDirPrefix(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.endsWith('/')) {
      return trimmed;
    }
    return '$trimmed/';
  }
}

class _MountWritebackPathCounts {
  int pending = 0;
  int running = 0;
}
