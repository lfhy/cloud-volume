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

  test(
    'removeTask only drops finished tasks and persists the change',
    () async {
      final queue = TransferQueue.instance;
      queue.bindApi(_FakeGateway());

      final running = queue.startTask(
        kind: TransferKind.upload,
        bucket: 'bucket-c',
        key: 'running.txt',
        localPath: '/tmp/running.txt',
      )..status = TransferStatus.running;
      final done = queue.startTask(
        kind: TransferKind.upload,
        bucket: 'bucket-c',
        key: 'done.txt',
        localPath: '/tmp/done.txt',
      )..status = TransferStatus.done;
      final failed = queue.startTask(
        kind: TransferKind.download,
        bucket: 'bucket-c',
        key: 'failed.txt',
        localPath: '/tmp/failed.txt',
      )..status = TransferStatus.failed;

      expect(queue.canRemoveTask(running.id), isFalse);
      expect(queue.canRemoveTask(done.id), isTrue);
      expect(queue.canRemoveTask(failed.id), isTrue);

      expect(queue.removeTask(running.id), isFalse);
      expect(queue.tasks.where((t) => t.id == running.id), isNotEmpty);

      expect(queue.removeTask(done.id), isTrue);
      expect(queue.tasks.where((t) => t.id == done.id), isEmpty);

      await queue.flushPersistenceForTest();
      await queue.restorePersistedStateForTest();
      expect(queue.tasks.where((t) => t.id == done.id), isEmpty);
      // Local producer closures cannot resume after restart; the backend's
      // unified task projection, rather than this compatibility queue, owns
      // any retained terminal history.
      expect(queue.tasks.where((t) => t.id == failed.id), isEmpty);
    },
  );

  test('removeTasks batch-removes only removable selection', () {
    final queue = TransferQueue.instance;
    queue.bindApi(_FakeGateway());

    final running = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-d',
      key: 'running.txt',
      localPath: '/tmp/running.txt',
    )..status = TransferStatus.running;
    final done = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-d',
      key: 'done.txt',
      localPath: '/tmp/done.txt',
    )..status = TransferStatus.done;
    final canceled = queue.startTask(
      kind: TransferKind.download,
      bucket: 'bucket-d',
      key: 'canceled.txt',
      localPath: '/tmp/canceled.txt',
    )..status = TransferStatus.canceled;

    expect(queue.removableTaskCount([running.id, done.id, canceled.id]), 2);

    final removed = queue.removeTasks([running.id, done.id, canceled.id]);
    expect(removed, 2);
    expect(queue.tasks.where((t) => t.id == running.id), isNotEmpty);
    expect(queue.tasks.where((t) => t.id == done.id), isEmpty);
    expect(queue.tasks.where((t) => t.id == canceled.id), isEmpty);
  });

  test('clearFinished purges done/failed/canceled but keeps active tasks', () {
    final queue = TransferQueue.instance;
    queue.bindApi(_FakeGateway());

    final running = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-e',
      key: 'running.txt',
      localPath: '/tmp/running.txt',
    )..status = TransferStatus.running;
    final pending = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-e',
      key: 'pending.txt',
      localPath: '/tmp/pending.txt',
    );
    queue
            .startTask(
              kind: TransferKind.upload,
              bucket: 'bucket-e',
              key: 'done.txt',
              localPath: '/tmp/done.txt',
            )
            .status =
        TransferStatus.done;
    queue
            .startTask(
              kind: TransferKind.download,
              bucket: 'bucket-e',
              key: 'failed.txt',
              localPath: '/tmp/failed.txt',
            )
            .status =
        TransferStatus.failed;

    final removed = queue.clearFinished();
    expect(removed, 2);
    final ids = queue.tasks.map((t) => t.id).toSet();
    expect(ids, containsAll([running.id, pending.id]));
    expect(ids.length, 2);
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
