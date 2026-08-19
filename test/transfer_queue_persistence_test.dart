// Transfer queue persistence tests verify restart recovery for finished and interrupted tasks.

import 'package:flutter_test/flutter_test.dart';
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

  test('restores finished tasks from persisted queue state', () async {
    final queue = TransferQueue.instance;
    final task = queue.startTask(
      kind: TransferKind.upload,
      bucket: 'bucket-a',
      key: 'folder/demo.txt',
      localPath: '/tmp/demo.txt',
    );
    queue.markTaskDone(task.id);
    await queue.flushPersistenceForTest();

    queue.resetForTest();
    await queue.restorePersistedStateForTest();

    expect(queue.tasks, hasLength(1));
    expect(queue.tasks.single.id, task.id);
    expect(queue.tasks.single.status, TransferStatus.done);
  });

  test('restores unfinished tasks as failed interrupted entries', () async {
    final queue = TransferQueue.instance;
    final task = queue.startTask(
      kind: TransferKind.download,
      bucket: 'bucket-b',
      key: 'video.mp4',
      localPath: '/tmp/video.mp4',
    );
    task.status = TransferStatus.running;
    task.bytesCompleted = 512;
    task.totalBytes = 1024;
    await queue.flushPersistenceForTest();

    queue.resetForTest();
    await queue.restorePersistedStateForTest();

    expect(queue.tasks, hasLength(1));
    expect(queue.tasks.single.id, task.id);
    expect(queue.tasks.single.status, TransferStatus.failed);
    expect(queue.tasks.single.error, contains('未完成'));
    expect(queue.tasks.single.bytesCompleted, 512);
  });

  test(
    'does not persist metadata-backed execution compatibility tasks',
    () async {
      final queue = TransferQueue.instance;
      queue.startTask(
        kind: TransferKind.upload,
        bucket: 'bucket-c',
        key: 'pending.txt',
        localPath: '/tmp/pending.txt',
        publishRemoteTask: false,
      );
      await queue.flushPersistenceForTest();

      queue.resetForTest();
      await queue.restorePersistedStateForTest();

      expect(queue.tasks, isEmpty);
    },
  );
}
