// Transfers page tests keep the header bulk actions wired to queue state.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/system_proxy_info.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/pages/transfers_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoteTaskStore.instance.resetForTest();
  });

  tearDown(() {
    RemoteTaskStore.instance.resetForTest();
  });

  testWidgets('batch cancel from header cancels eligible selected tasks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _TransfersPageFakeApi();
    final pendingUpload = const RemoteTask(
      id: 'sync:test:pending-upload',
      kind: RemoteTaskKind.upload,
      status: RemoteTaskStatus.waiting,
      bucket: 'bucket-a',
      targetPath: 'pending-upload.txt',
      cancelable: true,
    );
    final runningDownload = const RemoteTask(
      id: 'sync:test:running-download',
      kind: RemoteTaskKind.download,
      status: RemoteTaskStatus.running,
      bucket: 'bucket-a',
      targetPath: 'running-download.txt',
      cancelable: true,
    );
    final doneUpload = const RemoteTask(
      id: 'sync:test:done-upload',
      kind: RemoteTaskKind.upload,
      status: RemoteTaskStatus.done,
      bucket: 'bucket-a',
      targetPath: 'done-upload.txt',
    );
    api.tasks.addAll([pendingUpload, runningDownload, doneUpload]);

    await tester.pumpWidget(
      ShadApp(
        home: Material(
          child: TransfersPage(api: api, config: RemoteStorageConfig.empty()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(ListSelectionControl).first);
    await tester.pump();

    expect(find.text('取消 2'), findsOneWidget);
    await tester.tap(find.text('取消 2'));
    await tester.pump();

    expect(
      api.canceledTaskIds,
      containsAll([pendingUpload.id, runningDownload.id]),
    );
    expect(api.canceledTaskIds, isNot(contains(doneUpload.id)));
    await tester.pumpWidget(const SizedBox.shrink());
    RemoteTaskStore.instance.resetForTest();
  });
}

class _TransfersPageFakeApi implements RemoteStorageGateway {
  final List<String> canceledTaskIds = <String>[];
  final List<RemoteTask> tasks = <RemoteTask>[];

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async => RemoteTaskPage(items: List<RemoteTask>.from(tasks));

  @override
  Future<RemoteTask> getRemoteTask(String taskId) async =>
      tasks.firstWhere((task) => task.id == taskId);

  @override
  Future<bool> cancelRemoteTask(String taskId) async {
    canceledTaskIds.add(taskId);
    return true;
  }

  @override
  Future<bool> retryRemoteTask(String taskId) async => true;

  @override
  Future<bool> triggerRemoteTask(String taskId) async => true;

  @override
  Future<int> clearRemoteTaskHistory({
    String profileId = '',
    String bucket = '',
  }) async => 0;

  @override
  RemoteStorageCapabilities get capabilities =>
      const RemoteStorageCapabilities.desktop();

  @override
  Future<AuthSessionState> loadAuthSession() async =>
      const AuthSessionState.desktop();

  @override
  Future<BridgeBuildInfo> getBuildInfo() async => const BridgeBuildInfo();

  @override
  Future<SystemProxyInfo?> resolveSystemProxy() async => null;

  @override
  Future<void> validateAccountCredentials(RemoteStorageConfig config) async {}

  @override
  Future<Map<String, dynamic>?> matchPlatformAsset(
    List<Map<String, dynamic>> assets, {
    String? runtimeArchitecture,
  }) async => null;

  @override
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
  }) async => '';

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<String> startBaiduPanAuthorization() async =>
      throw UnimplementedError();

  @override
  Future<RemoteStorageConfig> authorizeBaiduPan(
    String displayName,
    String code,
  ) async => throw UnimplementedError();

  @override
  Future<void> cancelTransfer(String taskId) async {
    canceledTaskIds.add(taskId);
  }

  @override
  Future<bool> triggerTransfer(String taskId) async => false;

  @override
  Future<List<TransferSnapshot>> listTransferJobs() async =>
      const <TransferSnapshot>[];

  @override
  Future<BootstrapState> loadBootstrapState() async =>
      throw UnimplementedError();

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async =>
      throw UnimplementedError();
  @override
  Future<bool> updateProxySettings({
    required String proxyMode,
    required String proxyType,
    required String proxyHost,
    required String proxyPort,
    required String proxyUsername,
    required String proxyPassword,
  }) async => true;

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async =>
      throw UnimplementedError();

  @override
  Future<List<ProfileInfo>> listProfiles() async => throw UnimplementedError();

  @override
  Future<void> saveProfile(String name, RemoteStorageConfig config) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> deleteProfile(String name) async =>
      throw UnimplementedError();

  @override
  Future<BootstrapState> resetUserConfig() async => throw UnimplementedError();

  @override
  Future<CacheStats> getCacheStats(RemoteStorageConfig config) async =>
      throw UnimplementedError();

  @override
  Future<void> openCacheDirectory(RemoteStorageConfig config) async =>
      throw UnimplementedError();

  @override
  Future<CleanCacheResult> cleanCache(
    RemoteStorageConfig config, {
    required bool clearAll,
  }) async => throw UnimplementedError();

  @override
  Future<CachedFileRecord?> findCacheIndexRecord({
    required String bucket,
    required String objectKey,
  }) async => null;

  @override
  Future<void> upsertCacheIndexRecord(CachedFileRecord record) async {}

  @override
  Future<void> removeCacheIndexRecord({
    required String bucket,
    required String objectKey,
  }) async {}

  @override
  Future<List<CachedFileRecord>> removeCacheIndexPrefix({
    required String bucket,
    required String objectKeyPrefix,
  }) async => <CachedFileRecord>[];

  @override
  Future<BootstrapState> setActiveProfile(String name) async =>
      throw UnimplementedError();

  @override
  Future<List<BucketInfo>> listBuckets(
    RemoteStorageConfig config, {
    bool force = false,
  }) async => throw UnimplementedError();

  @override
  Future<BucketInfo> getBucketQuota(
    RemoteStorageConfig config,
    String bucket,
  ) async => BucketInfo(name: bucket);

  @override
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async => throw UnimplementedError();

  @override
  Future<ObjectListPage> listObjectPage(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String nextToken,
    int pageSize, {
    bool forceRefresh = false,
  }) async => throw UnimplementedError();

  @override
  Future<void> reorderProfiles(List<String> names) async {}

  @override
  Future<void> reorderBuckets(List<String> ids) async {}

  @override
  Future<List<String>> listBucketOrder() async => const <String>[];

  @override
  Future<ConfigBackupSettings> loadConfigBackupSettings() async =>
      const ConfigBackupSettings();

  @override
  Future<ConfigBackupSettings> saveConfigBackupSettings(
    ConfigBackupSettings settings,
  ) async => settings;

  @override
  Future<ConfigBackupSnapshot> backupConfigNow() async =>
      throw UnimplementedError();

  @override
  Future<List<ConfigBackupSnapshot>> listConfigBackups() async =>
      const <ConfigBackupSnapshot>[];

  @override
  Future<BootstrapState> restoreConfigBackup(String key) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteConfigBackup(String key) async =>
      throw UnimplementedError();

  @override
  Future<List<ConfigBackupSnapshot>> listConfigBackupsWithTarget(
    ConfigBackupTarget target,
  ) async => throw UnimplementedError();

  @override
  Future<BootstrapState> restoreConfigBackupWithTarget(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) async => throw UnimplementedError();

  @override
  Future<bool> verifyBackupPassword(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) async => throw UnimplementedError();

  @override
  Future<ObjectInfo> headObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
  ) async => throw UnimplementedError();

  @override
  Future<DirectoryAccess> directoryAccess(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async => const DirectoryAccess(writable: true, known: true);

  @override
  Future<void> createDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String name,
  ) async => throw UnimplementedError();

  @override
  Future<void> uploadBytes(
    RemoteStorageConfig config,
    String bucket,
    String key,
    Uint8List bytes,
    String taskId, {
    String fileName = '',
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String taskId, {
    bool permanent = false,
  }) async => throw UnimplementedError();

  @override
  Future<void> renameObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String newName,
  ) async => throw UnimplementedError();

  @override
  Future<void> copyObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  ) async => throw UnimplementedError();

  @override
  Future<void> moveObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  ) async => throw UnimplementedError();

  @override
  Future<ShareRecord> createShare(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String name,
    int durationSec,
  ) async => throw UnimplementedError();

  @override
  Future<List<ShareRecord>> listShares(RemoteStorageConfig config) async =>
      throw UnimplementedError();

  @override
  Future<ShareRecord> refreshShare(
    RemoteStorageConfig config,
    String id,
    int durationSec,
  ) async => throw UnimplementedError();

  @override
  Future<void> deleteShare(RemoteStorageConfig config, String id) async =>
      throw UnimplementedError();

  @override
  Future<List<TrashItem>> listTrash(
    RemoteStorageConfig config,
    String bucket,
  ) async => throw UnimplementedError();

  @override
  Future<TrashListPage> listTrashPage(
    RemoteStorageConfig config,
    String bucket,
    String nextToken,
    int pageSize,
  ) async => throw UnimplementedError();

  @override
  Future<void> restoreTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId, {
    String originalKey = '',
    bool isDirectory = false,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId,
  ) async => throw UnimplementedError();

  @override
  Future<void> clearTrash(RemoteStorageConfig config, String bucket) async =>
      throw UnimplementedError();

  @override
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async => throw UnimplementedError();

  @override
  Future<void> uploadDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String localPath,
    String taskId,
  ) async => throw UnimplementedError();

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async => throw UnimplementedError();

  @override
  Future<void> cleanupMounts() async => throw UnimplementedError();

  @override
  Future<int> cleanupStaleWindowsProcesses() async =>
      throw UnimplementedError();

  @override
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
    MountBucketOptions options,
  ) async => throw UnimplementedError();

  @override
  Future<BucketMountStatus> unmountBucket(
    String bucket, {
    bool removeLocalCache = false,
  }) async => throw UnimplementedError();

  @override
  Future<BucketMountStatus> getBucketMountStatus(String bucket) async =>
      throw UnimplementedError();

  @override
  Future<BucketMountStatus> openBucketMount(String bucket) async =>
      throw UnimplementedError();

  @override
  Uri? objectDownloadUri(String bucket, String key, {bool inline = false}) =>
      null;

  @override
  Uri? webDavUri(String bucket) => null;

  @override
  Future<List<SyncProfileRuntime>> listSyncProfiles() async =>
      <SyncProfileRuntime>[];

  @override
  Future<String> saveSyncProfile(SyncProfile profile) async => '';

  @override
  Future<void> deleteSyncProfile(String id) async {}

  @override
  Future<void> setLogLevel(String level) async {}

  @override
  Future<void> writeAppLog(
    String message, {
    String level = 'info',
    String tag = 'flutter',
  }) async {}

  @override
  Future<int> triggerSyncProfile(String id) async => 0;

  @override
  Future<Map<String, dynamic>> getP2PStatus() async =>
      throw UnsupportedError('P2P 不可用');

  @override
  Future<void> setP2PEnabled(bool enabled) async =>
      throw UnsupportedError('P2P 不可用');
}
