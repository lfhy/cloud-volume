// Widget tests verify the app boots and shows the Chinese bootstrap UI.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/mount_cache_cleanup_result.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/state/transfer_queue.dart';

void main() {
  setUp(() {
    TransferQueue.instance.resetForTest();
  });

  tearDown(() {
    TransferQueue.instance.resetForTest();
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
  });

  testWidgets('Setup page advances to WebDAV account form', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();
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
  });
}

/// Minimal fake API that does not need the Go bridge.
class _FakeApi implements RemoteStorageGateway {
  _FakeApi({required this.configured});
  final bool configured;

  @override
  Future<BootstrapState> loadBootstrapState() async => BootstrapState(
    configPath: '/tmp/.remote-storage/config.toml',
    configured: configured,
    config: configured
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
            rootPrefix: '',
            defaultDownloadDirectory: '',
            cacheDirectory: '',
            resolvedCacheDirectory: '/tmp/.remote-storage/cache',
            hideDotFiles: true,
            fileOpenMode: FileOpenMode.doubleClick,
            trashDirectoryName: '.trash',
            trashRetentionDays: -1,
            bucketSettings: <String, BucketSettings>{},
            writebackQuietSeconds: 10,
            mountMetadataCacheSeconds: 60,
            usePathStyle: true,
            windowsMountMode: WindowsMountMode.cloudFilesCached,
            windowsThisPcEntryEnabled: false,
            windowsWritebackConcurrency: 4,
          )
        : RemoteStorageConfig.empty(),
  );

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
  Future<void> cleanupMounts() async {}

  @override
  Future<int> cleanupStaleWindowsProcesses() async => 0;

  @override
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config) async => [];

  @override
  Future<void> saveProfile(String name, RemoteStorageConfig config) async {}

  @override
  Future<void> deleteProfile(String name) async {}

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
    int pageSize,
  ) async => const ObjectListPage(items: <ObjectInfo>[], nextToken: '');

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
    String taskId,
  ) async {}

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
    String trashId,
  ) async {}

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
      RemoteStorageConfig.empty();

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
  Future<BucketMountStatus> unmountBucket(String bucket) async =>
      const BucketMountStatus(
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

  @override
  Future<MountCacheCleanupResult> clearMountCache() async =>
      const MountCacheCleanupResult(removedCount: 0, freedBytes: 0);
}
