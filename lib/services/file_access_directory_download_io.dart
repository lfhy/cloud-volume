// Directory download helpers keep recursive list and parent progress together.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/file_access_download_cache_io.dart';
import 'package:remote_storage/services/file_access_transfer_request.dart';
import 'package:remote_storage/services/file_cache_store.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';

Future<void> runDirectoryDownloadToPath({
  required RemoteStorageGateway api,
  required RemoteStorageConfig config,
  required String bucket,
  required TransferTask task,
  required ObjectInfo directory,
  required String savePath,
  required FileCacheStore cacheStore,
  FileAccessDirectoryLister? directoryLister,
}) async {
  final root = Directory(savePath);
  await root.create(recursive: true);
  TransferQueue.instance.markTaskScanning(task.id);
  final files = await listFilesRecursively(
    api: api,
    config: config,
    bucket: bucket,
    prefix: directory.key,
    directoryLister: directoryLister,
  );
  TransferQueue.instance.updateTaskDirectoryTotals(
    task.id,
    totalItems: files.length,
    totalBytes: files.fold<int>(0, (sum, file) => sum + file.size),
  );
  final fileTasks = <_DirectoryDownloadFileTask>[
    for (final file in files)
      _DirectoryDownloadFileTask(
        object: file,
        localPath: _localPathForDirectoryFile(
          directory: directory,
          file: file,
          savePath: savePath,
        ),
        task: TransferQueue.instance.startTask(
          id: '${task.id}:file:${file.key}',
          kind: TransferKind.download,
          bucket: bucket,
          key: file.key,
          localPath: _localPathForDirectoryFile(
            directory: directory,
            file: file,
            savePath: savePath,
          ),
        ),
      ),
  ];
  for (final fileTask in fileTasks) {
    final file = fileTask.object;
    if (TransferQueue.instance.statusOf(task.id) == TransferStatus.canceled) {
      throw StateError('下载已取消');
    }
    final localPath = fileTask.localPath;
    await Directory(path.dirname(localPath)).create(recursive: true);
    TransferQueue.instance.updateTaskCurrentFile(
      task.id,
      key: file.key,
      totalBytes: file.size,
    );
    TransferQueue.instance.markTaskRunning(
      fileTask.task.id,
      statusDetail: 'directory_child',
      totalBytes: file.size,
      resetProgress: true,
    );
    try {
      final copied = await copyCachedObjectToPath(
        cacheStore: cacheStore,
        config: config,
        bucket: bucket,
        object: file,
        savePath: localPath,
      );
      if (!copied) {
        await api.downloadFile(
          config,
          bucket,
          file.key,
          localPath,
          fileTask.task.id,
        );
      }
      TransferQueue.instance.markTaskDone(fileTask.task.id);
    } catch (error) {
      TransferQueue.instance.markTaskFailed(fileTask.task.id, error);
      rethrow;
    }
    TransferQueue.instance.advanceTaskDirectoryFile(task.id, bytes: file.size);
  }
}

String _localPathForDirectoryFile({
  required ObjectInfo directory,
  required ObjectInfo file,
  required String savePath,
}) {
  final relativeKey = path.posix.relative(file.key, from: directory.key);
  return path.joinAll([savePath, ...path.posix.split(relativeKey)]);
}

class _DirectoryDownloadFileTask {
  const _DirectoryDownloadFileTask({
    required this.object,
    required this.localPath,
    required this.task,
  });

  final ObjectInfo object;
  final String localPath;
  final TransferTask task;
}

Future<List<ObjectInfo>> listFilesRecursively({
  required RemoteStorageGateway api,
  required RemoteStorageConfig config,
  required String bucket,
  required String prefix,
  FileAccessDirectoryLister? directoryLister,
}) async {
  final items = directoryLister == null
      ? await api.listObjects(config, bucket, prefix)
      : await directoryLister(prefix);
  final files = <ObjectInfo>[];
  for (final item in items) {
    if (item.key == prefix) {
      continue;
    }
    if (item.isDir) {
      files.addAll(
        await listFilesRecursively(
          api: api,
          config: config,
          bucket: bucket,
          prefix: item.key,
          directoryLister: directoryLister,
        ),
      );
    } else {
      files.add(item);
    }
  }
  return files;
}
