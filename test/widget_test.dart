// Widget tests verify the app boots and shows the Chinese bootstrap UI.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/system_proxy_info.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/widgets/file_manager_breadcrumb_bar.dart';

void main() {
  setUp(() {
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  tearDown(() {
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  testWidgets('App shows setup page when config is missing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('添加存储账号'), findsOneWidget);
    expect(find.text('S3 对象存储'), findsOneWidget);
    expect(find.text('WebDAV'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  testWidgets('Setup page advances to WebDAV account form', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下一步'));
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('添加 WebDAV 账号'), findsOneWidget);
    expect(find.text('WebDAV 地址'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('确认添加'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  testWidgets('App shows main layout when config exists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FileManagerPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  testWidgets('object load recovery edits the clicked bucket account', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final s3Config = RemoteStorageConfig.empty().copyWith(
      endpoint: 'https://s3.example.com',
      displayName: 'S3 Account',
      mappedBucketName: 'S3 Account',
      accessKeyId: 's3-access',
      secretAccessKey: 's3-secret',
      hasSecretAccessKey: true,
    );
    final baiduConfig = RemoteStorageConfig.empty().copyWith(
      endpoint: 'https://pan.baidu.com',
      storageType: StorageType.baiduPan,
      providerType: StorageProviderType.baiduPan,
      displayName: '百度账号',
      mappedBucketName: '百度网盘',
      accessKeyId: 'baidu-access',
      secretAccessKey: 'baidu-refresh',
      hasSecretAccessKey: true,
    );
    final api = _FakeApi(
      configured: true,
      configOverride: s3Config,
      profiles: const <ProfileInfo>[
        ProfileInfo(
          name: 's3-profile',
          displayName: 'S3 Account',
          storageType: StorageType.s3,
          providerType: StorageProviderType.s3,
          endpoint: 'https://s3.example.com',
          accessKeyId: 's3-access',
          active: true,
        ),
        ProfileInfo(
          name: 'baidu-profile',
          displayName: '百度账号',
          storageType: StorageType.baiduPan,
          providerType: StorageProviderType.baiduPan,
          endpoint: 'https://pan.baidu.com',
          accessKeyId: 'baidu-access',
        ),
      ],
      profileConfigs: <String, RemoteStorageConfig>{
        's3-profile': s3Config,
        'baidu-profile': baiduConfig,
      },
      bucketsByStorageType: const <StorageType, List<BucketInfo>>{
        StorageType.s3: <BucketInfo>[BucketInfo(name: 's3-bucket')],
        StorageType.baiduPan: <BucketInfo>[BucketInfo(name: '百度网盘')],
      },
      failingObjectStorageType: StorageType.baiduPan,
      baiduAuthorizationResult: baiduConfig.copyWith(
        accessKeyId: 'new-baidu-access',
        secretAccessKey: 'new-baidu-refresh',
      ),
    );

    await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('百度网盘'));
    await tester.pumpAndSettle();
    // The object-list error view exposes a secondary action that jumps to the
    // account-management page (instead of opening an in-place editor), so the
    // user can edit, disable, or re-enable the failing account in one place.
    // The sidebar also shows "账号管理", so find the button by type+text.
    final secondaryAction = find.descendant(
      of: find.byType(ShadButton),
      matching: find.text('账号管理'),
    );
    expect(secondaryAction, findsOneWidget);
    expect(find.text('编辑账号'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  testWidgets('bucket list renders after its initial quota resolution', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final quota = Completer<BucketInfo>();
    final config = RemoteStorageConfig.empty().copyWith(
      endpoint: 'https://pan.baidu.com',
      storageType: StorageType.baiduPan,
      providerType: StorageProviderType.baiduPan,
      displayName: '百度账号',
      mappedBucketName: '百度网盘',
      accessKeyId: 'test-access-token',
      secretAccessKey: 'test-refresh-token',
      hasSecretAccessKey: true,
    );
    final api = _FakeApi(
      configured: true,
      configOverride: config,
      buckets: const <BucketInfo>[BucketInfo(name: '百度网盘')],
      quotaResult: quota.future,
    );

    await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
    await tester.pump();
    await tester.pump();
    expect(api.quotaRequestCount, 1);

    quota.complete(
      const BucketInfo(
        name: '百度网盘',
        quotaBytes: 20 * 1024 * 1024 * 1024,
        usedBytes: 7 * 1024 * 1024 * 1024,
        quotaKnown: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7.0 GB / 20.0 GB'), findsOneWidget);
    await tester.tap(find.text('百度网盘'));
    await tester.pumpAndSettle();
    final breadcrumb = tester.widget<FileManagerBreadcrumbBar>(
      find.byType(FileManagerBreadcrumbBar),
    );
    breadcrumb.onOpenBucketList();
    await tester.pumpAndSettle();
    expect(api.quotaRequestCount, 1);
    expect(find.text('7.0 GB / 20.0 GB'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });
}

/// Minimal fake API that does not need the Go bridge.
class _FakeApi implements RemoteStorageGateway {
  _FakeApi({
    required this.configured,
    this.configOverride,
    this.buckets = const <BucketInfo>[],
    this.quotaResult,
    this.profiles = const <ProfileInfo>[],
    this.profileConfigs = const <String, RemoteStorageConfig>{},
    this.bucketsByStorageType = const <StorageType, List<BucketInfo>>{},
    this.failingObjectStorageType,
    this.baiduAuthorizationResult,
  });

  final bool configured;
  final RemoteStorageConfig? configOverride;
  final List<BucketInfo> buckets;
  final Future<BucketInfo>? quotaResult;

  @override
  Future<void> validateAccountCredentials(RemoteStorageConfig config) async {}
  final List<ProfileInfo> profiles;
  final Map<String, RemoteStorageConfig> profileConfigs;
  final Map<StorageType, List<BucketInfo>> bucketsByStorageType;
  final StorageType? failingObjectStorageType;
  final RemoteStorageConfig? baiduAuthorizationResult;
  int quotaRequestCount = 0;
  final Map<String, RemoteStorageConfig> savedProfiles =
      <String, RemoteStorageConfig>{};

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async => const RemoteTaskPage();

  @override
  Future<RemoteTask> getRemoteTask(String taskId) async =>
      throw UnsupportedError('任务不可用');

  @override
  Future<bool> cancelRemoteTask(String taskId) async => false;

  @override
  Future<bool> retryRemoteTask(String taskId) async => false;

  @override
  Future<bool> triggerRemoteTask(String taskId) async => false;

  @override
  Future<int> clearRemoteTaskHistory({
    String profileId = '',
    String bucket = '',
  }) async => 0;

  @override
  Future<BootstrapState> loadBootstrapState() async => BootstrapState(
    configPath: '/tmp/.remote-storage/config.toml',
    configured: configured,
    config:
        configOverride ??
        (configured
            ? const RemoteStorageConfig(
                endpoint: 'https://s3.example.com',
                storageType: StorageType.s3,
                providerType: StorageProviderType.s3,
                displayName: 'Test Account',
                mappedBucketName: 'Test Account',
                region: 'us-east-1',
                bucket: 'test-bucket',
                accessKeyId: 'AKIA_TEST',
                secretAccessKey: 'secret_test',
                hasSecretAccessKey: true,
                webdavUsername: 'webdav-user',
                webdavPassword: '',
                hasWebdavPassword: true,
                ftpUsername: '',
                ftpPassword: '',
                hasFtpPassword: false,
                ftpPort: 0,
                ftpAnonymous: false,
                rootPrefix: '',
                defaultDownloadDirectory: '',
                cacheDirectory: '',
                resolvedCacheDirectory: '/tmp/.remote-storage/cache',
                hideDotFiles: true,
                fileOpenMode: FileOpenMode.doubleClick,
                trashDirectoryName: '.trash',
                trashRetentionDays: -1,
                bucketSettings: <String, BucketSettings>{},
                bucketViews: <String, BucketViewSettings>{},
                writebackQuietSeconds: 10,
                mountMetadataCacheSeconds: 60,
                usePathStyle: true,
                windowsMountMode: WindowsMountMode.cloudFilesCached,
                windowsThisPcEntryEnabled: false,
                windowsWritebackConcurrency: 4,
                cacheAutoCleanupEnabled: false,
                cacheMaxSizeMb: 0,
                cacheMaxAgeDays: 0,
                jwanfsGatewayMode: JWanFSGatewayMode.auto,
                proxyMode: 'system',
                proxyType: 'http',
                proxyHost: '',
                proxyPort: '',
                proxyUsername: '',
                proxyPassword: '',
              )
            : RemoteStorageConfig.empty()),
    profiles: profiles,
  );

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
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async =>
      BootstrapState(
        configPath: '/tmp/.remote-storage/config.toml',
        configured: true,
        config: config,
      );

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
  ) async => baiduAuthorizationResult ?? (throw UnimplementedError());

  @override
  Future<void> cleanupMounts() async {}

  @override
  Future<int> cleanupStaleWindowsProcesses() async => 0;

  @override
  Future<List<BucketInfo>> listBuckets(
    RemoteStorageConfig config, {
    bool force = false,
  }) async {
    return bucketsByStorageType[config.storageType] ?? buckets;
  }

  @override
  Future<BucketInfo> getBucketQuota(
    RemoteStorageConfig config,
    String bucket,
  ) async {
    quotaRequestCount += 1;
    return quotaResult ?? BucketInfo(name: bucket);
  }

  @override
  Future<void> saveProfile(String name, RemoteStorageConfig config) async {
    savedProfiles[name] = config;
  }

  @override
  Future<Map<String, dynamic>> deleteProfile(String name) async =>
      const <String, dynamic>{};

  @override
  Future<BootstrapState> resetUserConfig() async => BootstrapState(
    configPath: '/tmp/.remote-storage/config.toml',
    configured: false,
    config: RemoteStorageConfig.empty(),
  );

  @override
  Future<CacheStats> getCacheStats(RemoteStorageConfig config) async =>
      const CacheStats(
        path: '/tmp/.remote-storage/cache',
        exists: false,
        sizeBytes: 0,
        fileCount: 0,
        lastModified: '',
      );

  @override
  Future<void> openCacheDirectory(RemoteStorageConfig config) async {}

  @override
  Future<CleanCacheResult> cleanCache(
    RemoteStorageConfig config, {
    required bool clearAll,
  }) async => const CleanCacheResult(
    beforeBytes: 0,
    afterBytes: 0,
    removed: 0,
    freedBytes: 0,
  );

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
      loadBootstrapState();

  @override
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async => [];

  @override
  Future<ObjectListPage> listObjectPage(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String nextToken,
    int pageSize, {
    bool forceRefresh = false,
  }) async {
    if (config.storageType == failingObjectStorageType) {
      throw StateError('object listing failed');
    }
    return const ObjectListPage(items: <ObjectInfo>[], nextToken: '');
  }

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
  ) async => ObjectInfo(key: key, size: 0, lastModified: '', isDir: false);

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
  ) async {}

  @override
  Future<void> deleteObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String taskId, {
    bool permanent = false,
  }) async {}

  @override
  Future<List<TrashItem>> listTrash(
    RemoteStorageConfig config,
    String bucket,
  ) async => [];

  @override
  Future<TrashListPage> listTrashPage(
    RemoteStorageConfig config,
    String bucket,
    String nextToken,
    int pageSize,
  ) async => const TrashListPage(items: <TrashItem>[], nextToken: '');

  @override
  Future<void> renameObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String newName,
  ) async {}

  @override
  Future<void> copyObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  ) async {}

  @override
  Future<void> moveObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  ) async {}

  @override
  Future<ShareRecord> createShare(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String name,
    int durationSec,
  ) async => const ShareRecord(
    id: 'share-id',
    bucket: 'bucket',
    key: 'file.txt',
    name: 'file.txt',
    url: 'https://example.com/share',
    expiresAt: '2026-05-27T12:00:00Z',
    durationSec: 3600,
    createdAt: '2026-05-27T11:00:00Z',
    updatedAt: '2026-05-27T11:00:00Z',
  );

  @override
  Future<List<ShareRecord>> listShares(RemoteStorageConfig config) async =>
      const [];

  @override
  Future<ShareRecord> refreshShare(
    RemoteStorageConfig config,
    String id,
    int durationSec,
  ) async => const ShareRecord(
    id: 'share-id',
    bucket: 'bucket',
    key: 'file.txt',
    name: 'file.txt',
    url: 'https://example.com/share',
    expiresAt: '2026-05-27T12:00:00Z',
    durationSec: 3600,
    createdAt: '2026-05-27T11:00:00Z',
    updatedAt: '2026-05-27T11:00:00Z',
  );

  @override
  Future<void> deleteShare(RemoteStorageConfig config, String id) async {}

  @override
  Future<void> restoreTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId, {
    String originalKey = '',
    bool isDirectory = false,
  }) async {}

  @override
  Future<void> deleteTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId,
  ) async {}

  @override
  Future<void> clearTrash(RemoteStorageConfig config, String bucket) async {}

  @override
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {}

  @override
  Future<void> uploadDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String localPath,
    String taskId,
  ) async {}

  @override
  Future<void> uploadBytes(
    RemoteStorageConfig config,
    String bucket,
    String key,
    Uint8List bytes,
    String taskId, {
    String fileName = '',
  }) async {}

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {}

  @override
  Uri? objectDownloadUri(String bucket, String key, {bool inline = false}) =>
      null;

  @override
  Uri? webDavUri(String bucket) => null;

  @override
  Future<void> cancelTransfer(String taskId) async {}

  @override
  Future<bool> triggerTransfer(String taskId) async => false;

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async =>
      profileConfigs[name] ?? configOverride ?? RemoteStorageConfig.empty();

  @override
  Future<List<ProfileInfo>> listProfiles() async => [];

  @override
  Future<List<TransferSnapshot>> listTransferJobs() async => [];

  @override
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
    MountBucketOptions options,
  ) async => const BucketMountStatus(
    mounted: false,
    bucket: '',
    mountPath: '',
    serverUrl: '',
    port: 0,
  );

  @override
  Future<BucketMountStatus> unmountBucket(
    String bucket, {
    bool removeLocalCache = false,
  }) async => const BucketMountStatus(
    mounted: false,
    bucket: '',
    mountPath: '',
    serverUrl: '',
    port: 0,
  );

  @override
  Future<BucketMountStatus> getBucketMountStatus(String bucket) async =>
      const BucketMountStatus(
        mounted: false,
        bucket: '',
        mountPath: '',
        serverUrl: '',
        port: 0,
      );

  @override
  Future<BucketMountStatus> openBucketMount(String bucket) async =>
      const BucketMountStatus(
        mounted: false,
        bucket: '',
        mountPath: '',
        serverUrl: '',
        port: 0,
      );

  // --- Directory sync stubs ---

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
