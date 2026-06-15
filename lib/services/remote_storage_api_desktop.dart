// Desktop bridge-backed API keeps the existing FFI workflow intact for native builds.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:remote_storage/bridge/remote_storage_bridge.dart';
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/models/mount_cache_cleanup_result.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

part 'remote_storage_api_desktop_shares.dart';
part 'remote_storage_api_desktop_paging.dart';

dynamic _invokeBridgeCall(
  String libraryPath,
  String method,
  Map<String, dynamic> payload,
) {
  final bridge = RemoteStorageBridge.openAtPath(libraryPath);
  return bridge.call(method, payload);
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
  RemoteStorageCapabilities get capabilities =>
      const RemoteStorageCapabilities.desktop();

  @override
  RemoteStorageBridge get bridgeHandle => _bridge;

  @override
  Future<dynamic> runBridgeCall(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) {
    final libraryPath = _bridge.libraryPath;
    final isolatePayload = payload.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(payload);
    // Keep synchronous FFI work off the UI isolate so large bridge calls do not
    // stall scrolling, hover states, or route transitions.
    return Isolate.run(
      () => _invokeBridgeCall(libraryPath, method, isolatePayload),
    );
  }

  @override
  Future<AuthSessionState> loadAuthSession() async {
    return const AuthSessionState.desktop();
  }

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<BootstrapState> loadBootstrapState() async {
    final payload =
        await runBridgeCall('load_bootstrap_state') as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async {
    final payload =
        await runBridgeCall('save_config', <String, dynamic>{
              'config': config.toJson(),
            })
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<String> startBaiduPanAuthorization() async {
    final result =
        await runBridgeCall('start_baidu_pan_authorization')
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return (result['authUrl'] ?? '').toString();
  }

  @override
  Future<RemoteStorageConfig> authorizeBaiduPan(
    String displayName,
    String code,
  ) async {
    final result = await runBridgeCall('authorize_baidu_pan', <String, dynamic>{
      'displayName': displayName,
      'code': code,
    });
    return RemoteStorageConfig.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async {
    final result = await runBridgeCall('load_profile', <String, dynamic>{
      'name': name,
    });
    return RemoteStorageConfig.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<ProfileInfo>> listProfiles() async {
    final result = await runBridgeCall('list_profiles');
    if (result is List) {
      return result
          .map((e) => ProfileInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<void> saveProfile(String name, RemoteStorageConfig config) async {
    await runBridgeCall('save_profile', <String, dynamic>{
      'name': name,
      'config': config.toJson(),
    });
  }

  @override
  Future<void> deleteProfile(String name) async {
    await runBridgeCall('delete_profile', <String, dynamic>{'name': name});
  }

  @override
  Future<BootstrapState> setActiveProfile(String name) async {
    final payload =
        await runBridgeCall('set_active_profile', <String, dynamic>{
              'name': name,
            })
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config) async {
    final result = await runBridgeCall('list_buckets', <String, dynamic>{
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
    String taskId,
  ) async {
    await runBridgeCall('delete_object', <String, dynamic>{
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
    await runBridgeCall('rename_object', <String, dynamic>{
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
    String trashId,
  ) async {
    await runBridgeCall('restore_trash_item', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'trashId': trashId,
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
  Future<int> cleanupStaleWindowsProcesses() async {
    final result = await runBridgeCall('cleanup_stale_windows_processes');
    if (result is Map<String, dynamic>) {
      return (result['count'] ?? 0) as int;
    }
    return 0;
  }

  @override
  Future<MountCacheCleanupResult> clearMountCache() async {
    final result = await runBridgeCall('clear_mount_cache');
    return MountCacheCleanupResult.fromJson(
      result as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  @override
  Future<BucketMountStatus> unmountBucket(String bucket) async {
    final result = await runBridgeCall('unmount_bucket', <String, dynamic>{
      'bucket': bucket,
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
