// Transfers page tests keep the header bulk actions wired to queue state.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/models/mount_cache_cleanup_result.dart';
import 'package:remote_storage/pages/transfers_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TransferQueue.instance.resetForTest();
  });

  tearDown(() {
    TransferQueue.instance.resetForTest();
  });

  testWidgets('batch cancel from header cancels eligible selected tasks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _TransfersPageFakeApi();
    final queue = TransferQueue.instance;
    queue.bindApi(api);

    final pendingUpload = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-a',
      key: 'pending-upload.txt',
      localPath: '/tmp/pending-upload.txt',
    );
    final runningDownload = queue.startTask(
      kind: TransferKind.download,
      bucket: 'bucket-a',
      key: 'running-download.txt',
      localPath: '/tmp/running-download.txt',
    )..status = TransferStatus.running;
    final doneUpload = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-a',
      key: 'done-upload.txt',
      localPath: '/tmp/done-upload.txt',
    )..status = TransferStatus.done;

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

    expect(find.text('批量取消 2'), findsOneWidget);
    await tester.tap(find.text('批量取消 2'));
    await tester.pump();

    expect(
      api.canceledTaskIds,
      containsAll([pendingUpload.id, runningDownload.id]),
    );
    expect(api.canceledTaskIds, isNot(contains(doneUpload.id)));
    expect(queue.statusOf(pendingUpload.id), TransferStatus.canceled);
    expect(queue.statusOf(runningDownload.id), TransferStatus.canceled);
    expect(queue.statusOf(doneUpload.id), TransferStatus.done);
    await tester.pumpWidget(const SizedBox.shrink());
    TransferQueue.instance.resetForTest();
  });
}

class _TransfersPageFakeApi implements RemoteStorageGateway {
  final List<String> canceledTaskIds = <String>[];

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
  Future<RemoteStorageConfig> loadProfile(String name) async =>
      throw UnimplementedError();

  @override
  Future<List<ProfileInfo>> listProfiles() async => throw UnimplementedError();

  @override
  Future<void> saveProfile(String name, RemoteStorageConfig config) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteProfile(String name) async => throw UnimplementedError();

  @override
  Future<BootstrapState> setActiveProfile(String name) async =>
      throw UnimplementedError();

  @override
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config) async =>
      throw UnimplementedError();

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
    int pageSize,
  ) async => throw UnimplementedError();

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
    String taskId,
  ) async => throw UnimplementedError();

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
    String trashId,
  ) async => throw UnimplementedError();

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
  Future<BucketMountStatus> unmountBucket(String bucket) async =>
      throw UnimplementedError();

  @override
  Future<BucketMountStatus> getBucketMountStatus(String bucket) async =>
      throw UnimplementedError();

  @override
  Future<BucketMountStatus> openBucketMount(String bucket) async =>
      throw UnimplementedError();

  @override
  Future<MountCacheCleanupResult> clearMountCache() async =>
      const MountCacheCleanupResult(removedCount: 0, freedBytes: 0);

  @override
  Uri? objectDownloadUri(String bucket, String key, {bool inline = false}) =>
      null;

  @override
  Uri? webDavUri(String bucket) => null;
}
