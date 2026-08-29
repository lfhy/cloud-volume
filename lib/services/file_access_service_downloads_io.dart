part of 'file_access_service_io.dart';

// Download picker helpers stay in a part file so the core access service is small.
extension FileAccessDownloadPicker on FileAccessService {
  Future<FileAccessTransferRequest?> prepareDownloadObjectWithPicker({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    FileAccessDirectoryLister? directoryLister,
  }) async {
    if (object.isDir) {
      final targetDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: '下载到',
        initialDirectory: await resolveDefaultDownloadDirectory(
          config.defaultDownloadDirectory,
        ),
      );
      if (targetDirectory == null || targetDirectory.trim().isEmpty) {
        return null;
      }
      return prepareDownloadObjectToPath(
        api: api,
        config: config,
        bucket: bucket,
        object: object,
        savePath: uniqueDownloadDirectoryPath(
          targetDirectory,
          object.displayName,
        ),
        directoryLister: directoryLister,
      );
    }
    final savePath = await _selectFileDownloadPath(config, object);
    if (savePath == null || savePath.trim().isEmpty) {
      return null;
    }

    return prepareDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: savePath,
      directoryLister: directoryLister,
    );
  }

  FileAccessTransferRequest startDownloadObjectWithPicker({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
    FileAccessDirectoryLister? directoryLister,
  }) {
    final task = TransferQueue.instance.startTask(
      kind: TransferKind.download,
      bucket: bucket,
      key: object.key,
      localPath: '',
    );
    TransferQueue.instance.markTaskSelectingPath(task.id);
    final completion = Future<void>.delayed(Duration.zero)
        .then((_) => _selectDownloadPath(config: config, object: object))
        .then((savePath) async {
          if (savePath == null || savePath.trim().isEmpty) {
            TransferQueue.instance.markTaskCanceled(task.id);
            throw StateError('已取消选择保存位置');
          }
          TransferQueue.instance.updateTaskLocalPath(task.id, savePath);
          await _runDownloadObjectToPath(
            api: api,
            config: config,
            bucket: bucket,
            object: object,
            savePath: savePath,
            task: task,
            directoryLister: directoryLister,
          );
          return savePath;
        });
    return FileAccessTransferRequest(task: task, completion: completion);
  }

  Future<FileAccessTransferRequest> prepareDownloadObjectToDefaultDirectory({
    required RemoteStorageGateway api,
    required RemoteStorageConfig config,
    required String bucket,
    required ObjectInfo object,
  }) async {
    final directory = await resolveDefaultDownloadDirectory(
      config.defaultDownloadDirectory,
    );
    if (directory == null || directory.trim().isEmpty) {
      throw StateError('无法解析默认下载目录，请使用另存为选择保存位置。');
    }
    return prepareDownloadObjectToPath(
      api: api,
      config: config,
      bucket: bucket,
      object: object,
      savePath: object.isDir
          ? uniqueDownloadDirectoryPath(directory, object.displayName)
          : uniqueDownloadPath(directory, object.displayName),
    );
  }

  Future<String?> _selectDownloadPath({
    required RemoteStorageConfig config,
    required ObjectInfo object,
  }) async {
    if (object.isDir) {
      final targetDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: '下载到',
        initialDirectory: await resolveDefaultDownloadDirectory(
          config.defaultDownloadDirectory,
        ),
      );
      if (targetDirectory == null || targetDirectory.trim().isEmpty) {
        return null;
      }
      return uniqueDownloadDirectoryPath(targetDirectory, object.displayName);
    }
    return _selectFileDownloadPath(config, object);
  }

  Future<String?> _selectFileDownloadPath(
    RemoteStorageConfig config,
    ObjectInfo object,
  ) async {
    // Android scoped storage grants the app an internal temporary directory,
    // not a stable filesystem path selected through the Storage Access
    // Framework. The Go bridge streams the object to that writable directory.
    if (Platform.isAndroid) {
      return uniqueDownloadPath(Directory.systemTemp.path, object.displayName);
    }
    final location = await getSaveLocation(suggestedName: object.displayName);
    return location?.path;
  }
}
