part of 'remote_storage_api_desktop.dart';

// Desktop storage bridge calls cover object mutations, transfers, mounts, and cache APIs.
mixin _RemoteStorageDesktopStorageApiMixin
    implements
        RemoteStorageGateway,
        ActiveMountQuery,
        AvailableDriveLetterQuery,
        WindowsWinFspQuery {
  Future<dynamic> runBridgeCall(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]);
  List<T> parseBridgeList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  );

  @override
  Future<List<BucketInfo>> listBuckets(
    RemoteStorageConfig config, {
    bool force = false,
  }) async {
    final result = await runBridgeCall('list_buckets', <String, dynamic>{
      'config': config.toJson(),
      if (force) 'force': true,
    });
    return parseBridgeList(result, (m) => BucketInfo.fromJson(m));
  }

  @override
  Future<void> validateAccountCredentials(RemoteStorageConfig config) async {
    await runBridgeCall('validate_account_credentials', <String, dynamic>{
      'config': config.toJson(),
    });
  }

  @override
  Future<BucketInfo> getBucketQuota(
    RemoteStorageConfig config,
    String bucket,
  ) async {
    final result = await runBridgeCall('get_bucket_quota', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
    });
    return BucketInfo.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<ObjectInfo> headObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
  ) async {
    final result = await runBridgeCall('head_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
    });
    return ObjectInfo.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<DirectoryAccess> directoryAccess(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async {
    final result = await runBridgeCall('directory_access', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'prefix': prefix,
    });
    return DirectoryAccess.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> createDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String name,
  ) async {
    await runBridgeCall('create_directory', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'prefix': prefix,
      'name': name,
    });
  }

  @override
  Future<void> deleteObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String taskId, {
    bool permanent = false,
  }) async {
    await runBridgeCall('delete_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'isDirectory': isDirectory,
      'taskId': taskId,
      'permanent': permanent,
    });
  }

  @override
  Future<void> renameObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String newName, {
    String taskId = '',
  }) async {
    await runBridgeCall('rename_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'isDirectory': isDirectory,
      'newName': newName,
      if (taskId.trim().isNotEmpty) 'taskId': taskId,
    });
  }

  @override
  Future<void> copyObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  ) async {
    await runBridgeCall('copy_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'sourceKey': sourceKey,
      'targetKey': targetKey,
      'isDirectory': isDirectory,
      'taskId': taskId,
    });
  }

  @override
  Future<void> moveObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  ) async {
    await runBridgeCall('move_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'sourceKey': sourceKey,
      'targetKey': targetKey,
      'isDirectory': isDirectory,
      'taskId': taskId,
    });
  }

  @override
  Future<void> restoreTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId, {
    String originalKey = '',
    bool isDirectory = false,
  }) async {
    await runBridgeCall('restore_trash_item', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'trashId': trashId,
      'originalKey': originalKey,
      'isDirectory': isDirectory,
    });
  }

  @override
  Future<void> deleteTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId,
  ) async {
    await runBridgeCall('delete_trash_item', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'trashId': trashId,
    });
  }

  @override
  Future<void> clearTrash(RemoteStorageConfig config, String bucket) async {
    await runBridgeCall('clear_trash', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
    });
  }

  @override
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {
    await runBridgeCall('upload_file', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'localPath': localPath,
      'taskId': taskId,
    });
  }

  @override
  Future<void> uploadDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String localPath,
    String taskId,
  ) async {
    await runBridgeCall('upload_directory', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': prefix,
      'localPath': localPath,
      'taskId': taskId,
    });
  }

  @override
  Future<void> uploadBytes(
    RemoteStorageConfig config,
    String bucket,
    String key,
    Uint8List bytes,
    String taskId, {
    String fileName = '',
  }) {
    throw UnsupportedError('桌面端上传仍使用本地文件路径链路');
  }

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {
    await runBridgeCall('download_file', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'localPath': localPath,
      'taskId': taskId,
    });
  }

  @override
  Uri? objectDownloadUri(String bucket, String key, {bool inline = false}) {
    return null;
  }

  @override
  Uri? webDavUri(String bucket) {
    return null;
  }

  @override
  Future<void> cancelTransfer(String taskId) async {
    await runBridgeCall('cancel_transfer', <String, dynamic>{'taskId': taskId});
  }

  @override
  Future<bool> triggerTransfer(String taskId) async {
    final result = await runBridgeCall('trigger_transfer', <String, dynamic>{
      'taskId': taskId,
    });
    if (result is Map<String, dynamic>) {
      return result['ok'] == true;
    }
    return false;
  }

  @override
  Future<List<TransferSnapshot>> listTransferJobs() async {
    final result = await runBridgeCall('list_transfer_jobs');
    return parseBridgeList(result, (m) => TransferSnapshot.fromJson(m));
  }

  @override
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
    MountBucketOptions options,
  ) async {
    final result = await runBridgeCall('mount_bucket', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'options': options.toJson(),
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> cleanupMounts() async {
    await runBridgeCall('cleanup_mounts');
  }

  @override
  Future<int> getActiveMountCount() async {
    final result = await runBridgeCall('get_active_mount_count');
    if (result is Map<String, dynamic>) {
      return (result['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  @override
  Future<List<String>> listAvailableDriveLetters() async {
    final result = await runBridgeCall('list_available_drive_letters');
    if (result is! List) return const <String>[];
    return result
        .map((value) => value.toString().trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<bool> listWindowsWinFspAvailable() async {
    try {
      final result = await runBridgeCall('list_windows_winfsp_available');
      if (result is Map<String, dynamic>) {
        return result['available'] == true;
      }
    } catch (_) {
      // Bridge not available; treat as WinFsp absent so the UI hides the engine.
    }
    return false;
  }

  @override
  Future<bool> installWindowsWinFsp() async {
    final result = await runBridgeCall('install_windows_winfsp');
    if (result is Map<String, dynamic>) {
      return result['available'] == true || result['ok'] == true;
    }
    return false;
  }

  @override
  Future<int> cleanupStaleWindowsProcesses() async {
    final result = await runBridgeCall('cleanup_stale_windows_processes');
    if (result is Map<String, dynamic>) {
      return (result['count'] ?? 0) as int;
    }
    return 0;
  }

  @override
  Future<BucketMountStatus> unmountBucket(
    String bucket, {
    bool removeLocalCache = false,
  }) async {
    final result = await runBridgeCall('unmount_bucket', <String, dynamic>{
      'bucket': bucket,
      'removeLocalCache': removeLocalCache,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> getBucketMountStatus(String bucket) async {
    final result = await runBridgeCall(
      'get_bucket_mount_status',
      <String, dynamic>{'bucket': bucket},
    );
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> openBucketMount(String bucket) async {
    final result = await runBridgeCall('open_bucket_mount', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }
}
