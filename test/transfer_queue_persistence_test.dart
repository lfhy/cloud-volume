// Transfer queue persistence tests verify restart recovery for finished and interrupted tasks.

import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
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

  test('does not restore finished local tasks as task-page history', () async {
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

    expect(queue.tasks, isEmpty);
  });

  test(
    'does not restore interrupted local tasks without a Go projection',
    () async {
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

      expect(queue.tasks, isEmpty);
    },
  );

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

  test(
    'invalidates pre-v2 persisted rows that lack ownership metadata',
    () async {
      SharedPreferences.setMockInitialValues({
        'transfer_queue.tasks.v1': jsonEncode([
          <String, dynamic>{
            'id': 'legacy-page-move',
            'kind': 'move',
            'bucket': 'bucket-a',
            'key': 'old.txt',
            'targetPath': 'new.txt',
            'status': 'done',
          },
        ]),
      });
      final queue = TransferQueue.instance;
      await queue.restorePersistedStateForTest();

      expect(queue.tasks, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('transfer_queue.tasks.v1'), isFalse);
    },
  );

  test('cleans a stale v1 key even when v2 data already exists', () async {
    SharedPreferences.setMockInitialValues({
      'transfer_queue.tasks.v1': '[]',
      'transfer_queue.tasks.v2': '[]',
    });
    await TransferQueue.instance.restorePersistedStateForTest();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('transfer_queue.tasks.v1'), isFalse);
  });
}
