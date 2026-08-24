// Transfer completion tests keep locally finalized progress internally consistent.

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/state/transfer_queue.dart';

void main() {
  setUp(() {
    RemoteTaskStore.instance.resetForTest();
    TransferQueue.instance.resetForTest();
  });
  tearDown(() {
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
  });

  test('markTaskDone completes both byte and item progress', () {
    final queue = TransferQueue.instance;
    final task = queue.startTask(
      kind: TransferKind.delete,
      bucket: 'bucket-a',
      key: 'folder/',
      localPath: '',
    );
    task.totalBytes = 4 * 1024 * 1024;
    task.bytesCompleted = task.totalBytes;
    task.totalItems = 20;
    task.itemsCompleted = 10;

    queue.markTaskDone(task.id);

    expect(task.status, TransferStatus.done);
    expect(task.bytesCompleted, task.totalBytes);
    expect(task.itemsCompleted, task.totalItems);
  });

  test('mirrors local task lifecycle into the unified task store', () {
    final queue = TransferQueue.instance;
    final task = queue.startTask(
      id: 'local-upload',
      kind: TransferKind.upload,
      bucket: 'bucket-a',
      key: 'file.txt',
      localPath: '/tmp/file.txt',
    );

    expect(
      RemoteTaskStore.instance.localTask('transfer:${task.id}')?.id,
      'transfer:${task.id}',
    );
    queue.markTaskRunning(task.id, totalBytes: 12);
    expect(
      RemoteTaskStore.instance
          .localTask('transfer:${task.id}')
          ?.progress
          .totalBytes,
      12,
    );
    queue.markTaskDone(task.id);
    // Terminal history comes from Go's projection; a local producer must not
    // leave a stale task-page row after the runtime monitor removes it.
    expect(RemoteTaskStore.instance.localTask('transfer:${task.id}'), isNull);
    expect(
      RemoteTaskStore.instance.executionTask('transfer:${task.id}')?.status,
      RemoteTaskStatus.done,
    );
    expect(queue.removeTask(task.id), isTrue);
    expect(RemoteTaskStore.instance.localTask('transfer:${task.id}'), isNull);
    expect(
      RemoteTaskStore.instance.executionTask('transfer:${task.id}'),
      isNull,
    );
  });

  test('metadata-backed producer does not create a duplicate remote row', () {
    final task = TransferQueue.instance.startTask(
      id: 'metadata-page-move',
      kind: TransferKind.move,
      bucket: 'bucket-a',
      key: 'old.txt',
      targetPath: 'new.txt',
      localPath: '',
      publishRemoteTask: false,
    );

    expect(RemoteTaskStore.instance.localTask('transfer:${task.id}'), isNull);
    TransferQueue.instance.markTaskDone(task.id);
    expect(RemoteTaskStore.instance.localTask('transfer:${task.id}'), isNull);
  });

  test(
    'metadata upload keeps transient progress outside the main task list',
    () async {
      final task = TransferQueue.instance.startTask(
        id: 'metadata-page-upload',
        kind: TransferKind.upload,
        bucket: 'bucket-a',
        key: 'file.txt',
        localPath: '/tmp/file.txt',
        publishRemoteTask: false,
      );

      expect(RemoteTaskStore.instance.tasks, isEmpty);
      expect(RemoteTaskStore.instance.hasActiveFileTransfers, isTrue);
      expect(
        RemoteTaskStore.instance
            .executionTask('transfer:${task.id}')
            ?.cancelable,
        isFalse,
      );
      expect(
        await RemoteTaskStore.instance.cancel('transfer:${task.id}'),
        isFalse,
      );
      expect(TransferQueue.instance.statusOf(task.id), TransferStatus.pending);
      expect(
        RemoteTaskStore.instance.executionTask('transfer:${task.id}'),
        isNotNull,
      );
      TransferQueue.instance.markTaskDone(task.id);
      expect(
        RemoteTaskStore.instance.executionTask('transfer:${task.id}')?.status,
        RemoteTaskStatus.done,
      );
    },
  );

  test(
    'RemoteTaskStore routes local cancellation to the producer facade',
    () async {
      final task = TransferQueue.instance.startTask(
        id: 'cancel-local',
        kind: TransferKind.upload,
        bucket: 'bucket-a',
        key: 'file.txt',
        localPath: '/tmp/file.txt',
      );
      expect(
        await RemoteTaskStore.instance.cancel('transfer:${task.id}'),
        isTrue,
      );
      expect(task.status, TransferStatus.canceled);
      expect(RemoteTaskStore.instance.localTask('transfer:${task.id}'), isNull);
      expect(
        RemoteTaskStore.instance.executionTask('transfer:${task.id}')?.status,
        RemoteTaskStatus.canceled,
      );
    },
  );

  test('mirrors legacy snapshot progress into the local task adapter', () {
    TransferQueue.instance.refreshFromSnapshots(const <TransferSnapshot>[
      TransferSnapshot(
        id: 'legacy-snapshot',
        type: 'sync_upload',
        bucket: 'bucket-a',
        key: 'folder/file.txt',
        localPath: '/tmp/file.txt',
        targetPath: '',
        status: 'running',
        statusDetail: '',
        createdAt: '2026-08-18T00:00:00Z',
        bytesCompleted: 4,
        totalBytes: 10,
        itemsCompleted: 0,
        totalItems: 0,
        currentFileKey: 'folder/file.txt',
        currentFileBytesCompleted: 4,
        currentFileTotalBytes: 10,
        speedBytes: 2,
      ),
    ]);
    final task = RemoteTaskStore.instance.localTask('transfer:legacy-snapshot');
    expect(task?.source, RemoteTaskSource.sync);
    expect(task?.progress.bytesCompleted, 4);
  });

  test(
    'does not project metadata physical phases as duplicate local tasks',
    () {
      TransferQueue.instance.refreshFromSnapshots(const <TransferSnapshot>[
        TransferSnapshot(
          id: 'metadata-op-namespace-7',
          type: 'upload',
          bucket: 'bucket-a',
          key: 'folder/file.txt',
          localPath: '/tmp/file.txt',
          targetPath: '',
          status: 'running',
          statusDetail: '',
          createdAt: '',
          bytesCompleted: 0,
          totalBytes: 0,
          itemsCompleted: 0,
          totalItems: 0,
          currentFileKey: '',
          currentFileBytesCompleted: 0,
          currentFileTotalBytes: 0,
          speedBytes: 0,
        ),
      ]);
      expect(
        RemoteTaskStore.instance.localTask('transfer:metadata-op-namespace-7'),
        isNull,
      );
    },
  );
}
