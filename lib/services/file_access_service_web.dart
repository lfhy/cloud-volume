// Browser file access uses server download URLs instead of local cache paths.

import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/file_access_transfer_request.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:url_launcher/url_launcher.dart';

class FileAccessService {
  FileAccessService._();

  static final FileAccessService instance = FileAccessService._();

  Future<FilePreviewSource> preparePreviewSource({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final target = api.objectDownloadUri(bucket, object.key, inline: true);
    if (target == null) {
      throw UnsupportedError('当前客户端不支持浏览器内预览');
    }
    return FilePreviewSource(uri: target);
  }

  Future<String> preparePreviewFilePath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    throw UnsupportedError('浏览器端不支持本地预览窗口');
  }

  Future<void> openObject({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final target = api.objectDownloadUri(bucket, object.key, inline: true);
    if (target == null) {
      throw UnsupportedError('当前客户端不支持浏览器内预览');
    }
    await _launch(target);
  }

  Future<FileAccessTransferRequest> prepareObjectForExternalOpen({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final target = api.objectDownloadUri(bucket, object.key, inline: true);
    if (target == null) {
      throw UnsupportedError('浏览器端不支持外部应用打开');
    }
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.download,
      bucket: bucket,
      key: object.key,
      localPath: object.displayName,
    );
    final completion = _launch(target)
        .then((_) {
          TransferQueue.instance.markTaskDone(task.id);
          return object.displayName;
        })
        .catchError((Object error) {
          TransferQueue.instance.markTaskFailed(task.id, error);
          throw error;
        });
    return FileAccessTransferRequest(task: task, completion: completion);
  }

  Future<void> openLocalPath(String localPath) async {}

  Future<FileAccessTransferRequest> prepareObjectForCacheDownload({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) {
    return prepareObjectForExternalOpen(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
  }

  // Web 端没有本地缓存目录，上传后无需（也无法）seed 本地预览缓存。
  Future<void> seedCacheFromUpload({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required String key,
    String? localSourcePath,
    List<int>? bytes,
  }) async {}

  Future<void> downloadObjectWithPicker({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final request = await prepareDownloadObjectWithPicker(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
    await request?.completion;
  }

  Future<FileAccessTransferRequest?> prepareDownloadObjectWithPicker({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    FileAccessDirectoryLister? directoryLister,
  }) {
    return prepareDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: object.displayName,
    );
  }

  FileAccessTransferRequest startDownloadObjectWithPicker({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    FileAccessDirectoryLister? directoryLister,
    bool Function()? canStartDownload,
  }) {
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.download,
      bucket: bucket,
      key: object.key,
      localPath: object.displayName,
    );
    if (canStartDownload != null && !canStartDownload()) {
      TransferQueue.instance.markTaskCanceled(task.id);
      return FileAccessTransferRequest(
        task: task,
        completion: Future.value(''),
      );
    }
    final completion = prepareDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: object.displayName,
      existingTask: task,
      directoryLister: directoryLister,
    ).then((request) => request.completion);
    return FileAccessTransferRequest(task: task, completion: completion);
  }

  Future<void> downloadObjectToDefaultDirectory({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final request = await prepareDownloadObjectToDefaultDirectory(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
    );
    await request.completion;
  }

  Future<FileAccessTransferRequest> prepareDownloadObjectToDefaultDirectory({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) {
    return prepareDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: object.displayName,
    );
  }

  Future<String> prepareLocalCopyPath({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    throw UnsupportedError('浏览器端不支持复制远端文件到系统剪贴板');
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
    if (object.isDir) {
      throw UnsupportedError('浏览器端暂不支持文件夹下载');
    }
    final target = api.objectDownloadUri(bucket, object.key);
    if (target == null) {
      throw UnsupportedError('当前客户端不支持浏览器下载');
    }
    final task =
        existingTask ??
        TransferQueue.instance.startTask(
          kind: TransferKind.download,
          bucket: bucket,
          key: object.key,
          localPath: savePath,
        );
    if (canStartDownload != null && !canStartDownload()) {
      TransferQueue.instance.markTaskCanceled(task.id);
      return FileAccessTransferRequest(
        task: task,
        completion: Future.value(''),
      );
    }
    final completion = _launch(target)
        .then((_) {
          TransferQueue.instance.markTaskDone(task.id);
          return savePath;
        })
        .catchError((Object error) {
          TransferQueue.instance.markTaskFailed(task.id, error);
          throw error;
        });
    return FileAccessTransferRequest(task: task, completion: completion);
  }

  Future<void> evictCacheForObject({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {}

  Future<void> _launch(Uri uri) async {
    final launched = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!launched) {
      throw StateError('无法打开浏览器下载地址');
    }
  }
}
