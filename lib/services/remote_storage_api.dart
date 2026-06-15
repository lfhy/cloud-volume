// Typed API helpers keep the Flutter pages focused on behavior instead of JSON plumbing.

import 'dart:isolate';

import 'package:remote_storage/bridge/remote_storage_bridge.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/models/mount_cache_cleanup_result.dart';

part 'remote_storage_api_shares.dart';
part 'remote_storage_api_paging.dart';

abstract class RemoteStorageGateway {
  Future<BootstrapState> loadBootstrapState();
  Future<BootstrapState> saveConfig(RemoteStorageConfig config);
  Future<RemoteStorageConfig> loadProfile(String name);
  Future<List<ProfileInfo>> listProfiles();
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config);
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  );
  Future<ObjectListPage> listObjectPage(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String nextToken,
    int pageSize,
  );
  Future<ObjectInfo> headObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
  );
  Future<void> createDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String name,
  );
  Future<void> deleteObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String taskId,
  );
  Future<void> renameObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String newName,
  );
  Future<void> copyObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  );
  Future<void> moveObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  );
  Future<ShareRecord> createShare(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String name,
    int durationSec,
  );
  Future<List<ShareRecord>> listShares(RemoteStorageConfig config);
  Future<ShareRecord> refreshShare(
    RemoteStorageConfig config,
    String id,
    int durationSec,
  );
  Future<void> deleteShare(RemoteStorageConfig config, String id);
  Future<List<TrashItem>> listTrash(RemoteStorageConfig config, String bucket);
  Future<TrashListPage> listTrashPage(
    RemoteStorageConfig config,
    String bucket,
    String nextToken,
    int pageSize,
  );
  Future<void> restoreTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId,
  );
  Future<void> deleteTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId,
  );
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  );
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  );
  Future<void> cancelTransfer(String taskId);
  Future<bool> triggerTransfer(String taskId);
  Future<List<TransferSnapshot>> listTransferJobs();
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
  );
  Future<BucketMountStatus> unmountBucket(String bucket);
  Future<BucketMountStatus> getBucketMountStatus(String bucket);
  Future<BucketMountStatus> openBucketMount(String bucket);
  Future<MountCacheCleanupResult> clearMountCache();
}

typedef RemoteStorageApiFactory = Future<RemoteStorageGateway> Function();

Future<RemoteStorageGateway> defaultRemoteStorageApiFactory() {
  return RemoteStorageApi.bootstrap();
}

class RemoteStorageApi
    with _RemoteStorageShareApiMixin, _RemoteStoragePagingApiMixin
    implements RemoteStorageGateway {
  RemoteStorageApi(this._bridge);

  static Future<RemoteStorageApi> bootstrap() async {
    final bridge = await RemoteStorageBridge.connect();
    return RemoteStorageApi(bridge);
  }

  final RemoteStorageBridge _bridge;

  @override
  RemoteStorageBridge get bridgeHandle => _bridge;

  @override
  Future<BootstrapState> loadBootstrapState() async {
    final payload =
        _bridge.call('load_bootstrap_state') as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async {
    final payload =
        _bridge.call('save_config', <String, dynamic>{
              'config': config.toJson(),
            })
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async {
    final result = _bridge.call('load_profile', <String, dynamic>{
      'name': name,
    });
    return RemoteStorageConfig.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<ProfileInfo>> listProfiles() async {
    final result = _bridge.call('list_profiles');
    if (result is List) {
      return result
          .map((e) => ProfileInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config) async {
    final result = _bridge.call('list_buckets', <String, dynamic>{
      'config': config.toJson(),
    });
    return parseBridgeList(result, (m) => BucketInfo.fromJson(m));
  }

  @override
  Future<ObjectInfo> headObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
  ) async {
    final result = _bridge.call('head_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
    });
    return ObjectInfo.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> createDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String name,
  ) async {
    _bridge.call('create_directory', <String, dynamic>{
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
    String taskId,
  ) async {
    _bridge.call('delete_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'isDirectory': isDirectory,
      'taskId': taskId,
    });
  }

  @override
  Future<void> renameObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String newName,
  ) async {
    _bridge.call('rename_object', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'key': key,
      'isDirectory': isDirectory,
      'newName': newName,
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
    await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(_bridge.libraryPath);
      bridge.call('copy_object', <String, dynamic>{
        'config': config.toJson(),
        'bucket': bucket,
        'sourceKey': sourceKey,
        'targetKey': targetKey,
        'isDirectory': isDirectory,
        'taskId': taskId,
      });
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
    await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(_bridge.libraryPath);
      bridge.call('move_object', <String, dynamic>{
        'config': config.toJson(),
        'bucket': bucket,
        'sourceKey': sourceKey,
        'targetKey': targetKey,
        'isDirectory': isDirectory,
        'taskId': taskId,
      });
    });
  }

  @override
  Future<void> restoreTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId,
  ) async {
    await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(_bridge.libraryPath);
      bridge.call('restore_trash_item', <String, dynamic>{
        'config': config.toJson(),
        'bucket': bucket,
        'trashId': trashId,
      });
    });
  }

  @override
  Future<void> deleteTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId,
  ) async {
    await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(_bridge.libraryPath);
      bridge.call('delete_trash_item', <String, dynamic>{
        'config': config.toJson(),
        'bucket': bucket,
        'trashId': trashId,
      });
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
    await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(_bridge.libraryPath);
      bridge.call('upload_file', <String, dynamic>{
        'config': config.toJson(),
        'bucket': bucket,
        'key': key,
        'localPath': localPath,
        'taskId': taskId,
      });
    });
  }

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {
    await Isolate.run(() {
      final bridge = RemoteStorageBridge.openAtPath(_bridge.libraryPath);
      bridge.call('download_file', <String, dynamic>{
        'config': config.toJson(),
        'bucket': bucket,
        'key': key,
        'localPath': localPath,
        'taskId': taskId,
      });
    });
  }

  @override
  Future<void> cancelTransfer(String taskId) async {
    _bridge.call('cancel_transfer', <String, dynamic>{'taskId': taskId});
  }

  @override
  Future<bool> triggerTransfer(String taskId) async {
    final result = _bridge.call('trigger_transfer', <String, dynamic>{
      'taskId': taskId,
    });
    if (result is Map<String, dynamic>) {
      return result['ok'] == true;
    }
    return false;
  }

  @override
  Future<List<TransferSnapshot>> listTransferJobs() async {
    final result = _bridge.call('list_transfer_jobs');
    return parseBridgeList(result, (m) => TransferSnapshot.fromJson(m));
  }

  @override
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
  ) async {
    final result = _bridge.call('mount_bucket', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> unmountBucket(String bucket) async {
    final result = _bridge.call('unmount_bucket', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> getBucketMountStatus(String bucket) async {
    final result = _bridge.call('get_bucket_mount_status', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> openBucketMount(String bucket) async {
    final result = _bridge.call('open_bucket_mount', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<MountCacheCleanupResult> clearMountCache() async {
    final result = _bridge.call('clear_mount_cache');
    return MountCacheCleanupResult.fromJson(
      result as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  @override
  List<T> parseBridgeList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (result is List) {
      return result.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }
}
