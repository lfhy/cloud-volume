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
    expect(
      RemoteTaskStore.instance
          .localTask('transfer:${task.id}')
          ?.status
          .wireName,
      'done',
    );
    expect(queue.removeTask(task.id), isTrue);
    expect(RemoteTaskStore.instance.localTask('transfer:${task.id}'), isNull);
  });

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
      expect(
        RemoteTaskStore.instance.localTask('transfer:${task.id}')?.status,
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
}
