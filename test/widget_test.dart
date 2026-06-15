// Smoke test: verify the app boots and shows the Chinese bootstrap UI.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
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
    expect(find.text('登录远程存储'), findsOneWidget);
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
            region: 'us-east-1',
            bucket: 'test-bucket',
            accessKeyId: 'AKIA_TEST',
            secretAccessKey: 'secret_test',
            rootPrefix: '',
            defaultDownloadDirectory: '',
            hideDotFiles: true,
            fileOpenMode: FileOpenMode.doubleClick,
            trashDirectoryName: '.trash',
            trashRetentionDays: 30,
            usePathStyle: true,
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
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config) async => [];

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
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {}

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {}

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
