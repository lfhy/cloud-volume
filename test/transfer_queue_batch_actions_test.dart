// Transfer queue batch-action tests keep multi-select task controls in the queue layer.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TransferQueue.instance.resetForTest();
  });

  tearDown(() {
    TransferQueue.instance.resetForTest();
  });

  test('queue reports batch-eligible start and cancel counts', () {
    final queue = TransferQueue.instance;
    queue.bindApi(_FakeGateway());

    final pendingUpload = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-a',
      key: 'pending.txt',
      localPath: '/tmp/pending.txt',
    );
    final runningDownload = queue.startTask(
      kind: TransferKind.download,
      bucket: 'bucket-a',
      key: 'running.txt',
      localPath: '/tmp/running.txt',
    )..status = TransferStatus.running;
    final doneUpload = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-a',
      key: 'done.txt',
      localPath: '/tmp/done.txt',
    )..status = TransferStatus.done;

    expect(
      queue.triggerableTaskCount([
        pendingUpload.id,
        runningDownload.id,
        doneUpload.id,
      ]),
      1,
    );
    expect(
      queue.cancelableTaskCount([
        pendingUpload.id,
        runningDownload.id,
        doneUpload.id,
      ]),
      2,
    );
    expect(queue.canTriggerTask(pendingUpload.id), isTrue);
    expect(queue.canCancelTask(runningDownload.id), isTrue);
    expect(queue.canCancelTask(doneUpload.id), isFalse);
  });

  test('batch actions only call the API for eligible tasks', () async {
    final api = _FakeGateway();
    final queue = TransferQueue.instance;
    queue.bindApi(api);

    final pendingUpload = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-b',
      key: 'pending-upload.txt',
      localPath: '/tmp/pending-upload.txt',
    );
    final runningDownload = queue.startTask(
      kind: TransferKind.download,
      bucket: 'bucket-b',
      key: 'running-download.txt',
      localPath: '/tmp/running-download.txt',
    )..status = TransferStatus.running;
    final pendingCopy = queue.startTask(
      kind: TransferKind.copy,
      bucket: 'bucket-b',
      key: 'pending-copy.txt',
      localPath: '/tmp/pending-copy.txt',
    );
    final doneUpload = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-b',
      key: 'done-upload.txt',
      localPath: '/tmp/done-upload.txt',
    )..status = TransferStatus.done;

    final canceled = await queue.cancelTasks([
      runningDownload.id,
      pendingCopy.id,
      doneUpload.id,
    ]);
    expect(canceled, 2);
    expect(
      api.canceledTaskIds,
      orderedEquals([runningDownload.id, pendingCopy.id]),
    );

    final triggered = await queue.triggerTasksNow([
      pendingUpload.id,
      pendingCopy.id,
      doneUpload.id,
    ]);
    expect(triggered, 1);
    expect(api.triggeredTaskIds, orderedEquals([pendingUpload.id]));
  });
}

class _FakeGateway extends Fake implements RemoteStorageGateway {
  final List<String> canceledTaskIds = <String>[];
  final List<String> triggeredTaskIds = <String>[];

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
  Future<bool> triggerTransfer(String taskId) async {
    triggeredTaskIds.add(taskId);
    return true;
  }

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
  Uri? objectDownloadUri(String bucket, String key, {bool inline = false}) =>
      null;

  @override
  Uri? webDavUri(String bucket) => null;

  @override
  Future<List<TransferSnapshot>> listTransferJobs() async =>
      const <TransferSnapshot>[];
}
