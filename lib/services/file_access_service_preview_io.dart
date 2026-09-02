part of 'file_access_service_io.dart';

// Preview access owns inline-size limits and cached-file handoffs.

const int _maximumInlineMarkdownPreviewBytes = 8 * 1024 * 1024;

extension FileAccessPreview on FileAccessService {
  Future<FilePreviewSource> preparePreviewSource({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final watch = Stopwatch()..start();
    final cachePath = await _ensureCachedObject(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      maximumInlineBytes: _inlinePreviewByteLimit(object),
    );
    unawaited(
      AppLog.debug(
        'prepare source cache ready bucket=$bucket key=${object.key} elapsedMs=${watch.elapsedMilliseconds} path=$cachePath',
        tag: 'preview',
      ),
    );
    final readWatch = Stopwatch()..start();
    final bytes = await File(cachePath).readAsBytes();
    unawaited(
      AppLog.debug(
        'prepare source read bytes bucket=$bucket key=${object.key} readMs=${readWatch.elapsedMilliseconds} totalMs=${watch.elapsedMilliseconds} bytes=${bytes.length}',
        tag: 'preview',
      ),
    );
    return FilePreviewSource(bytes: bytes);
  }

  Future<String> preparePreviewFilePath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) {
    return _ensureCachedObject(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      maximumInlineBytes: _inlinePreviewByteLimit(object),
    );
  }

  Future<void> openObject({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final cachePath = await _ensureCachedObject(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
    await LocalFileOpener.openPath(cachePath);
  }

  Future<FileAccessTransferRequest> prepareObjectForExternalOpen({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) {
    return prepareObjectForCacheDownload(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
  }

  /// Downloads into the app-managed cache so Android can later hand the
  /// verified file to another application without requesting a save location.
  Future<FileAccessTransferRequest> prepareObjectForCacheDownload({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) {
    return _ensureCachedObjectRequest(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
  }

  Future<void> openLocalPath(String localPath) {
    return LocalFileOpener.openPath(localPath);
  }

  int? _inlinePreviewByteLimit(ObjectInfo object) =>
      previewKindForName(object.displayName) == FilePreviewKind.markdown
      ? _maximumInlineMarkdownPreviewBytes
      : null;
}
