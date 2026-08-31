// File access service owns click-to-open, explicit download, and cache bookkeeping.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/file_cache_store.dart';
import 'package:remote_storage/services/file_access_download_cache_io.dart';
import 'package:remote_storage/services/file_access_directory_download_io.dart';
import 'package:remote_storage/services/file_access_paths_io.dart';
import 'package:remote_storage/services/file_access_transfer_request.dart';
import 'package:remote_storage/services/local_file_opener.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/utils/app_log.dart';
import 'package:remote_storage/utils/default_download_directory.dart';

part 'file_access_service_downloads_io.dart';

class FileAccessService {
  FileAccessService._();

  static final FileAccessService instance = FileAccessService._();

  final FileCacheStore _cacheStore = FileCacheStore.instance;

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

  /// 上传成功后把本地副本登记进预览缓存，让"双击打开"命中缓存而无需重下。
  ///
  /// 以远端 headObject 返回的 size/mtime 为准写入缓存记录，否则
  /// [FileCacheStore.findUsableCachePath] 的 `_matchesRemoteObject` 比对会
  /// 失败。本地源文件被 copy 进缓存目录，既是预览缓存，也可作为上传重试
  /// 或后续同步的本地副本。任何异常都被吞掉——这只是缓存优化，绝不应让
  /// 缓存写入失败影响上传成功的语义。
  Future<void> seedCacheFromUpload({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required String key,
    String? localSourcePath,
    List<int>? bytes,
  }) async {
    assert(
      localSourcePath != null || bytes != null,
      'seedCacheFromUpload 需要本地源路径或字节内容之一',
    );
    try {
      final remoteObject = await api.headObject(config, bucket, key);
      final cachePath = await _cacheStore.cachePathFor(
        config.resolvedCacheDirectory,
        bucket,
        key,
      );
      final cacheFile = File(cachePath);
      // 缓存目录可能已有残留（同名对象被删后又重建），先清掉再写入。
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      if (localSourcePath != null) {
        await File(localSourcePath).copy(cachePath);
      } else {
        await cacheFile.writeAsBytes(bytes!, flush: true);
      }
      await _cacheStore.upsertCacheRecord(
        api: api,
        bucket: bucket,
        object: remoteObject,
        localPath: cachePath,
      );
    } catch (_) {
      // 缓存 seeding 失败不阻断上传流程；下次双击会退回正常下载。
    }
  }

  Future<String> _ensureCachedObject({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final request = await _ensureCachedObjectRequest(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
    return request.completion;
  }

  Future<FileAccessTransferRequest> _ensureCachedObjectRequest({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final watch = Stopwatch()..start();
    unawaited(
      AppLog.debug(
        'ensure start bucket=$bucket key=${object.key}',
        tag: 'preview',
      ),
    );
    final headWatch = Stopwatch()..start();
    final remoteObject = await api.headObject(config, bucket, object.key);
    unawaited(
      AppLog.debug(
        'head done bucket=$bucket key=${object.key} phaseMs=${headWatch.elapsedMilliseconds} totalMs=${watch.elapsedMilliseconds} size=${remoteObject.size} lastModified=${remoteObject.lastModified}',
        tag: 'preview',
      ),
    );
    final cacheFindWatch = Stopwatch()..start();
    final cachedPath = await _cacheStore.findUsableCachePath(
      api,
      config.resolvedCacheDirectory,
      bucket,
      remoteObject,
    );
    unawaited(
      AppLog.debug(
        'cache find done bucket=$bucket key=${object.key} phaseMs=${cacheFindWatch.elapsedMilliseconds} totalMs=${watch.elapsedMilliseconds} hit=${cachedPath != null}',
        tag: 'preview',
      ),
    );
    if (cachedPath != null) {
      return FileAccessTransferRequest(completion: Future.value(cachedPath));
    }

    final pathWatch = Stopwatch()..start();
    final cachePath = await _cacheStore.cachePathFor(
      config.resolvedCacheDirectory,
      bucket,
      object.key,
    );
    unawaited(
      AppLog.debug(
        'cache path done bucket=$bucket key=${object.key} phaseMs=${pathWatch.elapsedMilliseconds} totalMs=${watch.elapsedMilliseconds} path=$cachePath',
        tag: 'preview',
      ),
    );
    final existingTask = TransferQueue.instance.findActiveTask(
      kind: TransferKind.download,
      bucket: bucket,
      key: object.key,
      localPath: cachePath,
    );
    if (existingTask != null) {
      unawaited(
        AppLog.debug(
          'reuse download task bucket=$bucket key=${object.key} taskId=${existingTask.id} totalMs=${watch.elapsedMilliseconds}',
          tag: 'preview',
        ),
      );
      return FileAccessTransferRequest(
        task: existingTask,
        completion: waitForTransferTaskSuccess(
          existingTask.id,
        ).then((_) => cachePath),
      );
    }

    final task = TransferQueue.instance.startTask(
      kind: TransferKind.download,
      bucket: bucket,
      key: object.key,
      localPath: cachePath,
    );
    unawaited(
      AppLog.debug(
        'download task created bucket=$bucket key=${object.key} taskId=${task.id} totalMs=${watch.elapsedMilliseconds}',
        tag: 'preview',
      ),
    );
    final completion =
        _runDownload(
          api: api,
          config: config,
          task: task,
          onSuccess: () async {
            final indexWatch = Stopwatch()..start();
            await _cacheStore.upsertCacheRecord(
              api: api,
              bucket: bucket,
              object: remoteObject,
              localPath: cachePath,
            );
            unawaited(
              AppLog.debug(
                'cache upsert done bucket=$bucket key=${object.key} phaseMs=${indexWatch.elapsedMilliseconds} totalMs=${watch.elapsedMilliseconds}',
                tag: 'preview',
              ),
            );
          },
          onFailure: () async {
            await _cacheStore.removeCacheRecord(
              api: api,
              bucket: bucket,
              objectKey: remoteObject.key,
              localPath: cachePath,
              deleteFile: true,
            );
          },
        ).then((_) {
          unawaited(
            AppLog.debug(
              'download complete bucket=$bucket key=${object.key} totalMs=${watch.elapsedMilliseconds}',
              tag: 'preview',
            ),
          );
          return cachePath;
        });
    return FileAccessTransferRequest(task: task, completion: completion);
  }

  Future<String> prepareLocalCopyPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    if (object.isDir) {
      throw UnsupportedError('暂不支持复制文件夹到系统剪贴板');
    }
    return _ensureCachedObject(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
  }

  Future<void> downloadObjectToPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    required String savePath,
    FileAccessDirectoryLister? directoryLister,
  }) async {
    final request = await prepareDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: savePath,
      directoryLister: directoryLister,
    );
    await request.completion;
  }

  Future<FileAccessTransferRequest> prepareDownloadObjectToPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    required String savePath,
    TransferTask? existingTask,
    FileAccessDirectoryLister? directoryLister,
    bool Function()? canStartDownload,
  }) async {
    if (savePath.trim().isEmpty) {
      return FileAccessTransferRequest(completion: Future.value(savePath));
    }
    final task =
        existingTask ??
        TransferQueue.instance.startTask(
          kind: TransferKind.download,
          bucket: bucket,
          key: object.key,
          localPath: savePath,
        );
    if (task.localPath != savePath) {
      TransferQueue.instance.updateTaskLocalPath(task.id, savePath);
    }
    if (canStartDownload != null && !canStartDownload()) {
      TransferQueue.instance.markTaskCanceled(task.id);
      return FileAccessTransferRequest(
        task: task,
        completion: Future.value(''),
      );
    }
    final completion = _runDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: savePath,
      task: task,
      directoryLister: directoryLister,
    ).then((_) => savePath);
    return FileAccessTransferRequest(task: task, completion: completion);
  }

  Future<void> _runDownloadObjectToPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    required String savePath,
    required TransferTask task,
    FileAccessDirectoryLister? directoryLister,
  }) {
    if (object.isDir) {
      return _runDirectoryDownload(
        api: api,
        config: config,
        task: task,
        directory: object,
        savePath: savePath,
        directoryLister: directoryLister,
      );
    }
    return runDownloadToPathWithCache(
      cacheStore: _cacheStore,
      api: api,
      config: config,
      task: task,
      object: object,
      savePath: savePath,
      remoteDownload: () => _runDownload(
        api: api,
        config: config,
        task: task,
        onFailure: () => deleteFileIfExists(savePath),
      ),
    );
  }

  Future<void> evictCacheForObject({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    if (object.isDir) {
      await _cacheStore.removeCachePrefix(
        api: api,
        bucket: bucket,
        objectKeyPrefix: object.key,
        deleteFiles: true,
      );
      return;
    }
    await _cacheStore.removeCacheRecord(
      api: api,
      bucket: bucket,
      objectKey: object.key,
      deleteFile: true,
    );
  }

  Future<void> _runDownload({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required TransferTask task,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFailure,
  }) async {
    try {
      await api.downloadFile(
        config,
        task.bucket,
        task.key,
        task.localPath,
        task.id,
      );
      TransferQueue.instance.markTaskDone(task.id);
      if (onSuccess != null) {
        await onSuccess();
      }
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      if (onFailure != null) {
        await onFailure();
      }
      if (TransferQueue.instance.statusOf(task.id) == TransferStatus.canceled) {
        throw StateError('下载已取消');
      }
      rethrow;
    }
  }

  Future<void> _runDirectoryDownload({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required TransferTask task,
    required ObjectInfo directory,
    required String savePath,
    FileAccessDirectoryLister? directoryLister,
  }) async {
    try {
      await runDirectoryDownloadToPath(
        api: api,
        config: config,
        bucket: task.bucket,
        task: task,
        directory: directory,
        savePath: savePath,
        cacheStore: _cacheStore,
        directoryLister: directoryLister,
      );
      TransferQueue.instance.markTaskDone(task.id);
    } catch (error) {
      TransferQueue.instance.markTaskFailed(task.id, error);
      if (TransferQueue.instance.statusOf(task.id) == TransferStatus.canceled) {
        throw StateError('下载已取消');
      }
      rethrow;
    }
  }
}
