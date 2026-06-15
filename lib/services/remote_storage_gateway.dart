// Shared API contracts keep Flutter pages platform-agnostic across desktop and web.

import 'dart:typed_data';

import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/mount_cache_cleanup_result.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';

/// Client-side capability flags let pages adjust behavior without forking routes.
class RemoteStorageCapabilities {
  const RemoteStorageCapabilities({
    required this.supportsMounts,
    required this.supportsNativeOpen,
    required this.supportsDownloadDirectory,
    required this.supportsSessionLogin,
    required this.supportsWebDavAccess,
    required this.supportsBrowserTransfers,
    required this.supportsDesktopWindowControls,
  });

  const RemoteStorageCapabilities.desktop()
    : supportsMounts = true,
      supportsNativeOpen = true,
      supportsDownloadDirectory = true,
      supportsSessionLogin = false,
      supportsWebDavAccess = false,
      supportsBrowserTransfers = false,
      supportsDesktopWindowControls = true;

  const RemoteStorageCapabilities.web()
    : supportsMounts = false,
      supportsNativeOpen = false,
      supportsDownloadDirectory = false,
      supportsSessionLogin = true,
      supportsWebDavAccess = true,
      supportsBrowserTransfers = true,
      supportsDesktopWindowControls = false;

  final bool supportsMounts;
  final bool supportsNativeOpen;
  final bool supportsDownloadDirectory;
  final bool supportsSessionLogin;
  final bool supportsWebDavAccess;
  final bool supportsBrowserTransfers;
  final bool supportsDesktopWindowControls;
}

abstract class RemoteStorageGateway {
  RemoteStorageCapabilities get capabilities;

  Future<AuthSessionState> loadAuthSession();
  Future<void> login(String username, String password);
  Future<void> logout();

  Future<BootstrapState> loadBootstrapState();
  Future<BootstrapState> saveConfig(RemoteStorageConfig config);
  Future<String> startBaiduPanAuthorization();
  Future<RemoteStorageConfig> authorizeBaiduPan(
    String displayName,
    String code,
  );
  Future<RemoteStorageConfig> loadProfile(String name);
  Future<List<ProfileInfo>> listProfiles();
  Future<void> saveProfile(String name, RemoteStorageConfig config);
  Future<void> deleteProfile(String name);
  Future<BootstrapState> setActiveProfile(String name);
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
  Future<DirectoryAccess> directoryAccess(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
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
  Future<void> clearTrash(RemoteStorageConfig config, String bucket);
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  );
  Future<void> uploadDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String localPath,
    String taskId,
  );
  Future<void> uploadBytes(
    RemoteStorageConfig config,
    String bucket,
    String key,
    Uint8List bytes,
    String taskId, {
    String fileName = '',
  });
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  );
  Uri? objectDownloadUri(String bucket, String key, {bool inline = false});
  Uri? webDavUri(String bucket);
  Future<void> cancelTransfer(String taskId);
  Future<bool> triggerTransfer(String taskId);
  Future<List<TransferSnapshot>> listTransferJobs();
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
    MountBucketOptions options,
  );
  Future<void> cleanupMounts();
  Future<int> cleanupStaleWindowsProcesses();
  Future<BucketMountStatus> unmountBucket(String bucket);
  Future<BucketMountStatus> getBucketMountStatus(String bucket);
  Future<BucketMountStatus> openBucketMount(String bucket);
  Future<MountCacheCleanupResult> clearMountCache();
}

typedef RemoteStorageApiFactory = Future<RemoteStorageGateway> Function();

class MountBucketOptions {
  const MountBucketOptions({this.mountPath = '', this.readOnly = false});

  final String mountPath;
  final bool readOnly;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mountPath': mountPath.trim(),
      'readOnly': readOnly,
    };
  }
}
