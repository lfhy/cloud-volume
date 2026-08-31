part of 'file_manager_page.dart';

// Captures an upload's source location so a late completion refreshes only
// that directory, while always invalidating its cache for future navigation.

extension _FileManagerPageUploads on _FileManagerPageState {
  TransferTask? _queueLocalUpload(String localPath, {String? relativeKey}) {
    if (_activeBucket == null ||
        _activeBucketEntry == null ||
        localPath.trim().isEmpty) {
      return null;
    }
    if (!_ensureCurrentDirectoryWritable()) return null;
    final bucket = _activeBucket!;
    final uploadKey = relativeKey == null || relativeKey.trim().isEmpty
        ? path.basename(localPath)
        : relativeKey;
    final key = _prefix + uploadKey;
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.upload,
      bucket: bucket,
      key: key,
      localPath: localPath,
      publishRemoteTask: !_usesMetadataRemoteTasks,
    );
    final bucketEntry = _activeBucketEntry!;
    final sourcePrefix = _prefix;
    final sourceListingViewGeneration = _listingViewGeneration;
    unawaited(
      _runUploadTask(
        task,
        bucketEntry,
        sourcePrefix,
        sourceListingViewGeneration,
      ),
    );
    return task;
  }

  TransferTask? _queueBrowserUpload(String fileName, Uint8List bytes) {
    if (_activeBucket == null || _activeBucketEntry == null) return null;
    if (!_ensureCurrentDirectoryWritable()) return null;
    final bucket = _activeBucket!;
    final key = _prefix + fileName;
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.upload,
      bucket: bucket,
      key: key,
      localPath: fileName,
      publishRemoteTask: !_usesMetadataRemoteTasks,
    );
    final bucketEntry = _activeBucketEntry!;
    final sourcePrefix = _prefix;
    final sourceListingViewGeneration = _listingViewGeneration;
    unawaited(
      _runBrowserUploadTask(
        task,
        bucketEntry,
        bytes,
        fileName,
        sourcePrefix,
        sourceListingViewGeneration,
      ),
    );
    return task;
  }

  Future<void> _runUploadTask(
    TransferTask task,
    FileManagerBucketEntry bucket,
    String sourcePrefix,
    int sourceListingViewGeneration,
  ) async {
    try {
      await widget.api.uploadFile(
        bucket.config,
        task.bucket,
        task.key,
        task.localPath,
        task.id,
      );
      TransferQueue.instance.markTaskDone(task.id);
      unawaited(
        FileAccessService.instance.seedCacheFromUpload(
          api: widget.api,
          config: bucket.config,
          bucket: task.bucket,
          key: task.key,
          localSourcePath: task.localPath,
        ),
      );
      await _finishUploadRefresh(
        bucket,
        sourcePrefix,
        sourceListingViewGeneration,
      );
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      await _finishUploadRefresh(
        bucket,
        sourcePrefix,
        sourceListingViewGeneration,
      );
    }
  }

  Future<void> _runBrowserUploadTask(
    TransferTask task,
    FileManagerBucketEntry bucket,
    Uint8List bytes,
    String fileName,
    String sourcePrefix,
    int sourceListingViewGeneration,
  ) async {
    try {
      await widget.api.uploadBytes(
        bucket.config,
        task.bucket,
        task.key,
        bytes,
        task.id,
        fileName: fileName,
      );
      TransferQueue.instance.markTaskDone(task.id);
      unawaited(
        FileAccessService.instance.seedCacheFromUpload(
          api: widget.api,
          config: bucket.config,
          bucket: task.bucket,
          key: task.key,
          bytes: bytes,
        ),
      );
      await _finishUploadRefresh(
        bucket,
        sourcePrefix,
        sourceListingViewGeneration,
      );
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      await _finishUploadRefresh(
        bucket,
        sourcePrefix,
        sourceListingViewGeneration,
      );
    }
  }

  Future<void> _finishUploadRefresh(
    FileManagerBucketEntry bucket,
    String sourcePrefix,
    int sourceListingViewGeneration,
  ) async {
    _invalidateObjectListingCache(bucketId: bucket.id);
    if (!_isCurrentObjectMutationSource(
      bucket,
      sourcePrefix,
      sourceListingViewGeneration,
    )) {
      return;
    }
    await _reloadObjectsAfterBucketMutation(bucket, sourcePrefix);
  }
}
