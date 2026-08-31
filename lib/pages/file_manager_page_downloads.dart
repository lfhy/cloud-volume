part of 'file_manager_page.dart';

// File download commands retain their source while the native save picker is open.
extension _FileManagerPageDownloads on _FileManagerPageState {
  Future<void> _downloadObject(ObjectInfo object) async {
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) return;
    final bucket = bucketEntry.bucket.name;
    final config = bucketEntry.config;
    final prefix = _prefix;
    final sourceListingViewGeneration = _listingViewGeneration;
    final mobileRequest = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
    );
    if (!_isCurrentObjectMutationCommand(
      bucketEntry,
      prefix,
      sourceListingViewGeneration,
      mobileRequest,
    )) {
      return;
    }
    try {
      bool isCurrentDownloadCommand() => _isCurrentObjectMutationCommand(
        bucketEntry,
        prefix,
        sourceListingViewGeneration,
        mobileRequest,
      );
      final request = FileAccessService.instance.startDownloadObjectWithPicker(
        api: widget.api,
        config: config,
        bucket: bucket,
        object: object,
        directoryLister: _downloadDirectoryLister(
          bucketEntry: bucketEntry,
          mobileRequest: mobileRequest,
          listingViewGeneration: sourceListingViewGeneration,
          requestStillCurrent: isCurrentDownloadCommand,
        ),
        canStartDownload: isCurrentDownloadCommand,
      );
      _watchDownloadRequest(request);
      await _showDownloadProgressDialogForTasks(_tasksForRequests([request]));
    } catch (error) {
      _showPageError(error);
    }
  }
}
