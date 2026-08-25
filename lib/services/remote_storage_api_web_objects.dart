part of 'remote_storage_api_web.dart';

mixin _RemoteStorageWebObjectApiMixin implements RemoteStorageGateway {
  Future<dynamic> _invoke(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]);
  List<T> _parseList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  );

  @override
  Future<ObjectInfo> headObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
  ) async {
    final result = await _invoke('head_object', <String, dynamic>{
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
    final result = await _invoke('directory_access', <String, dynamic>{
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
    await _invoke('create_directory', <String, dynamic>{
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
    await _invoke('delete_object', <String, dynamic>{
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
    await _invoke('rename_object', <String, dynamic>{
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
    await _invoke('copy_object', <String, dynamic>{
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
    await _invoke('move_object', <String, dynamic>{
      'bucket': bucket,
      'sourceKey': sourceKey,
      'targetKey': targetKey,
      'isDirectory': isDirectory,
      'taskId': taskId,
    });
  }

  @override
  Future<ShareRecord> createShare(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String name,
    int durationSec,
  ) async {
    final result = await _invoke('create_share', <String, dynamic>{
      'bucket': bucket,
      'key': key,
      'name': name,
      'durationSec': durationSec,
    });
    return ShareRecord.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<ShareRecord>> listShares(RemoteStorageConfig config) async {
    final result = await _invoke('list_shares');
    return _parseList(result, (m) => ShareRecord.fromJson(m));
  }

  @override
  Future<ShareRecord> refreshShare(
    RemoteStorageConfig config,
    String id,
    int durationSec,
  ) async {
    final result = await _invoke('refresh_share', <String, dynamic>{
      'id': id,
      'durationSec': durationSec,
    });
    return ShareRecord.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> deleteShare(RemoteStorageConfig config, String id) async {
    await _invoke('delete_share', <String, dynamic>{'id': id});
  }

  @override
  Future<void> restoreTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId, {
    String originalKey = '',
    bool isDirectory = false,
  }) async {
    await _invoke('restore_trash_item', <String, dynamic>{
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
    await _invoke('delete_trash_item', <String, dynamic>{
      'bucket': bucket,
      'trashId': trashId,
    });
  }

  @override
  Future<void> clearTrash(RemoteStorageConfig config, String bucket) async {
    await _invoke('clear_trash', <String, dynamic>{'bucket': bucket});
  }
}
