// Download cache helpers copy usable cached files before remote downloads.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/file_cache_store.dart';
import 'package:remote_storage/state/transfer_queue.dart';

Future<bool> copyCachedObjectToPath({
  required FileCacheStore cacheStore,
  required RemoteStorageConfig config,
  required String bucket,
  required ObjectInfo object,
  required String savePath,
}) async {
  final cachedPath = await cacheStore.findUsableCachePath(
    config.resolvedCacheDirectory,
    bucket,
    object,
  );
  if (cachedPath == null) {
    return false;
  }
  await Directory(path.dirname(savePath)).create(recursive: true);
  await File(cachedPath).copy(savePath);
  return true;
}

Future<void> runDownloadToPathWithCache({
  required FileCacheStore cacheStore,
  required RemoteStorageConfig config,
  required TransferTask task,
  required ObjectInfo object,
  required String savePath,
  required Future<void> Function() remoteDownload,
}) async {
  final copied = await copyCachedObjectToPath(
    cacheStore: cacheStore,
    config: config,
    bucket: task.bucket,
    object: object,
    savePath: savePath,
  );
  if (copied) {
    TransferQueue.instance.markTaskDone(task.id);
    return;
  }
  await remoteDownload();
}

Future<void> deleteFileIfExists(String localPath) async {
  final file = File(localPath);
  if (await file.exists()) {
    await file.delete();
  }
}
