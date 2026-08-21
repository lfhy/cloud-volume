// Shared API contracts keep Flutter pages platform-agnostic across desktop and web.

import 'dart:typed_data';

import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/system_proxy_info.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';

part 'remote_storage_gateway_models.dart';

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
    required this.supportsCacheDirectoryOpen,
  });

  const RemoteStorageCapabilities.desktop()
    : supportsMounts = true,
      supportsNativeOpen = true,
      supportsDownloadDirectory = true,
      supportsSessionLogin = false,
      supportsWebDavAccess = false,
      supportsBrowserTransfers = false,
      supportsDesktopWindowControls = true,
      supportsCacheDirectoryOpen = true;

  const RemoteStorageCapabilities.web()
    : supportsMounts = false,
      supportsNativeOpen = false,
      supportsDownloadDirectory = false,
      supportsSessionLogin = true,
      supportsWebDavAccess = true,
      supportsBrowserTransfers = true,
      supportsDesktopWindowControls = false,
      supportsCacheDirectoryOpen = false;

  final bool supportsMounts;
  final bool supportsNativeOpen;
  final bool supportsDownloadDirectory;
  final bool supportsSessionLogin;
  final bool supportsWebDavAccess;
  final bool supportsBrowserTransfers;
  final bool supportsDesktopWindowControls;
  final bool supportsCacheDirectoryOpen;
}

abstract class RemoteStorageGateway {
  RemoteStorageCapabilities get capabilities;

  Future<AuthSessionState> loadAuthSession();
  Future<void> login(String username, String password);
  Future<void> logout();

  Future<BootstrapState> loadBootstrapState();
  Future<BridgeBuildInfo> getBuildInfo();

  /// Matches the correct release asset for this platform via the Go bridge.
  /// Returns the matched asset fields and installer type, or null if no match.
  /// The Go side owns the asset name suffixes (synced with build scripts).
  Future<Map<String, dynamic>?> matchPlatformAsset(
    List<Map<String, dynamic>> assets, {
    String? runtimeArchitecture,
  });

  /// Resolves the host-level system proxy (e.g. Windows Settings manual proxy).
  /// Returns null when no usable system proxy is configured.
  Future<SystemProxyInfo?> resolveSystemProxy();
  Future<BootstrapState> saveConfig(RemoteStorageConfig config);
  Future<void> validateAccountCredentials(RemoteStorageConfig config);
  Future<bool> updateProxySettings({
    required String proxyMode,
    required String proxyType,
    required String proxyHost,
    required String proxyPort,
    required String proxyUsername,
    required String proxyPassword,
  });
  Future<String> startBaiduPanAuthorization();
  Future<RemoteStorageConfig> authorizeBaiduPan(
    String displayName,
    String code,
  );
  Future<RemoteStorageConfig> loadProfile(String name);
  Future<List<ProfileInfo>> listProfiles();
  Future<void> saveProfile(String name, RemoteStorageConfig config);
  Future<Map<String, dynamic>> deleteProfile(String name);
  Future<BootstrapState> resetUserConfig();
  Future<BootstrapState> setActiveProfile(String name);
  Future<void> reorderProfiles(List<String> names);
  Future<void> reorderBuckets(List<String> ids);
  Future<List<String>> listBucketOrder();
  Future<ConfigBackupSettings> loadConfigBackupSettings() async =>
      throw UnsupportedError('配置备份不可用');
  Future<ConfigBackupSettings> saveConfigBackupSettings(
    ConfigBackupSettings settings,
  ) async => throw UnsupportedError('配置备份不可用');
  Future<ConfigBackupSnapshot> backupConfigNow() async =>
      throw UnsupportedError('配置备份不可用');
  Future<List<ConfigBackupSnapshot>> listConfigBackups() async =>
      throw UnsupportedError('配置备份不可用');
  Future<BootstrapState> restoreConfigBackup(String key) async =>
      throw UnsupportedError('配置备份不可用');
  Future<void> deleteConfigBackup(String key) async =>
      throw UnsupportedError('配置备份不可用');
  Future<List<ConfigBackupSnapshot>> listConfigBackupsWithTarget(
    ConfigBackupTarget target,
  ) async => throw UnsupportedError('配置备份不可用');
  Future<BootstrapState> restoreConfigBackupWithTarget(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) async => throw UnsupportedError('配置备份不可用');
  Future<bool> verifyBackupPassword(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) async => throw UnsupportedError('配置备份不可用');
  Future<List<BucketInfo>> listBuckets(
    RemoteStorageConfig config, {
    bool force = false,
  });
  Future<BucketInfo> getBucketQuota(RemoteStorageConfig config, String bucket);
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
    int pageSize, {
    bool forceRefresh = false,
  });
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
    String taskId, {
    bool permanent = false,
  });
  Future<void> renameObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String newName, {
    String taskId = '',
  });
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
    String trashId, {
    String originalKey = '',
    bool isDirectory = false,
  });
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

  /// Unified logical remote-operation queue. Implementations may temporarily
  /// adapt legacy transfer snapshots while metadata projection is rolling out.
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async {
    throw UnsupportedError('统一远端任务队列不可用');
  }

  Future<RemoteTask> getRemoteTask(String taskId) async {
    throw UnsupportedError('统一远端任务队列不可用');
  }

  Future<bool> cancelRemoteTask(String taskId) async {
    throw UnsupportedError('统一远端任务队列不可用');
  }

  Future<bool> retryRemoteTask(String taskId) async {
    throw UnsupportedError('统一远端任务队列不可用');
  }

  Future<bool> triggerRemoteTask(String taskId) async {
    throw UnsupportedError('统一远端任务队列不可用');
  }

  Future<int> clearRemoteTaskHistory({
    String profileId = '',
    String bucket = '',
    List<String> taskIds = const <String>[],
  }) async {
    throw UnsupportedError('统一远端任务队列不可用');
  }

  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
    MountBucketOptions options,
  );
  Future<void> cleanupMounts();
  Future<int> cleanupStaleWindowsProcesses();
  Future<int> sweepOrphanMounts();
  Future<CacheStats> getCacheStats(RemoteStorageConfig config);
  Future<void> openCacheDirectory(RemoteStorageConfig config);
  Future<CleanCacheResult> cleanCache(
    RemoteStorageConfig config, {
    required bool clearAll,
  });
  Future<CachedFileRecord?> findCacheIndexRecord({
    required String bucket,
    required String objectKey,
  });
  Future<void> upsertCacheIndexRecord(CachedFileRecord record);
  Future<void> removeCacheIndexRecord({
    required String bucket,
    required String objectKey,
  });
  Future<List<CachedFileRecord>> removeCacheIndexPrefix({
    required String bucket,
    required String objectKeyPrefix,
  });
  Future<BucketMountStatus> unmountBucket(
    String bucket, {
    bool removeLocalCache = false,
  });
  Future<BucketMountStatus> getBucketMountStatus(String bucket);
  Future<BucketMountStatus> openBucketMount(String bucket);

  // --- Directory sync ---
  Future<List<SyncProfileRuntime>> listSyncProfiles();
  Future<String> saveSyncProfile(SyncProfile profile);
  Future<void> deleteSyncProfile(String id);
  Future<int> triggerSyncProfile(String id);

  /// Desktop: update the backend log filter; Web keeps the value locally.
  Future<void> setLogLevel(String level) async {}

  /// Desktop: append a line through the shared backend log filter; Web: no-op.
  Future<void> writeAppLog(
    String message, {
    String level = 'info',
    String tag = 'flutter',
  });

  /// Triggers a background download + install + relaunch of a release asset.
  /// Returns the transfer task id so the caller can observe the matching
  /// [RemoteTaskStore] projection. The download/install runs entirely in Go,
  /// while the Dart side only renders the unified task state.
  Future<String> installApp({
    required String assetUrl,
    required String assetName,
    required int assetSize,
    required String assetDigest,
    required String installerType,
    required String mirrorPrefix,
    required RemoteStorageConfig config,
    required String proxyMode,
    required String proxyType,
    required String proxyHost,
    required String proxyPort,
    required String proxyUsername,
    required String proxyPassword,
  });

  /// Returns the current P2P status: enabled flag, device ID, and discovered peers.
  Future<Map<String, dynamic>> getP2PStatus() async =>
      throw UnsupportedError('P2P 不可用');

  /// Enables or disables P2P LAN discovery at runtime.
  Future<void> setP2PEnabled(bool enabled) async =>
      throw UnsupportedError('P2P 不可用');
}

/// Optional desktop capability for warning before exit unmounts active roots.
abstract interface class ActiveMountQuery {
  Future<int> getActiveMountCount();
}

/// Optional Windows capability used to populate Cloud Files drive choices.
abstract interface class AvailableDriveLetterQuery {
  Future<List<String>> listAvailableDriveLetters();
}

/// Optional Windows capability that reports whether the WinFsp driver is
/// installed, so the mount engine selector can enable/disable the WinFsp
/// option without attempting a real mount first. The optional install method
/// extracts the embedded WinFsp MSI and elevates msiexec for a silent install.
abstract interface class WindowsWinFspQuery {
  Future<bool> listWindowsWinFspAvailable();
  Future<bool> installWindowsWinFsp();
}

typedef RemoteStorageApiFactory = Future<RemoteStorageGateway> Function();
