// RemoteTaskStore tests ensure endpoint failures never resurrect legacy rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/remote_task_display.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/remote_task_store.dart';

void main() {
  setUp(() => RemoteTaskStore.instance.resetForTest());
  tearDown(() => RemoteTaskStore.instance.resetForTest());

  test('keeps the unified store empty when the endpoint fails', () async {
    final api = _FakeGateway()..error = StateError('offline');
    RemoteTaskStore.instance.bindApi(api);
    await Future<void>.delayed(Duration.zero);
    expect(RemoteTaskStore.instance.tasks, isEmpty);
    expect(RemoteTaskStore.instance.lastError, isA<StateError>());
  });

  test(
    'retains effective tasks and profile filtering from the endpoint',
    () async {
      final api = _FakeGateway()
        ..page = const RemoteTaskPage(
          items: <RemoteTask>[
            RemoteTask(
              id: 'sync:ns:g1',
              kind: RemoteTaskKind.upload,
              status: RemoteTaskStatus.running,
              profileId: 'profile-a',
            ),
            RemoteTask(
              id: 'sync:ns:g2',
              kind: RemoteTaskKind.mkdir,
              status: RemoteTaskStatus.waiting,
              profileId: 'profile-b',
            ),
          ],
        );
      RemoteTaskStore.instance.bindApi(api);
      await Future<void>.delayed(Duration.zero);
      expect(RemoteTaskStore.instance.tasks, hasLength(2));
      expect(
        RemoteTaskStore.instance.tasksForProfile('profile-a'),
        hasLength(1),
      );
      expect(RemoteTaskStore.instance.hasActive, isTrue);
    },
  );

  test(
    'remote snapshots override a local task with the same transfer id',
    () async {
      const id = 'transfer:local-upload';
      RemoteTaskStore.instance.publishLocalTask(
        const RemoteTask(
          id: id,
          kind: RemoteTaskKind.upload,
          status: RemoteTaskStatus.running,
          source: RemoteTaskSource.local,
        ),
      );
      final api = _FakeGateway()
        ..page = const RemoteTaskPage(
          items: <RemoteTask>[
            RemoteTask(
              id: id,
              kind: RemoteTaskKind.upload,
              status: RemoteTaskStatus.done,
              source: RemoteTaskSource.runtime,
            ),
          ],
        );
      RemoteTaskStore.instance.bindApi(api);
      await Future<void>.delayed(Duration.zero);
      // bindApi fires an unawaited active-only poll; wait it out and then
      // request the terminal runtime row explicitly from history.
      await Future<void>.delayed(Duration.zero);
      await RemoteTaskStore.instance.refresh(
        const RemoteTaskFilter(includeHistory: true),
      );
      final task = RemoteTaskStore.instance.tasks.single;
      expect(task.source, RemoteTaskSource.runtime);
      expect(task.status, RemoteTaskStatus.done);
      expect(RemoteTaskStore.instance.removeLocalTask(id), isTrue);
    },
  );

  test('purges physical metadata snapshots left by an older bridge', () async {
    final api = _FakeGateway()
      ..page = const RemoteTaskPage(
        items: <RemoteTask>[
          RemoteTask(
            id: 'transfer:metadata-op-old-7',
            kind: RemoteTaskKind.write,
            status: RemoteTaskStatus.verifying,
          ),
          RemoteTask(
            id: 'sync:ns:g7',
            kind: RemoteTaskKind.write,
            status: RemoteTaskStatus.done,
          ),
        ],
      );
    RemoteTaskStore.instance.bindApi(api);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await RemoteTaskStore.instance.refresh(
      const RemoteTaskFilter(includeHistory: true),
    );
    expect(RemoteTaskStore.instance.tasks, hasLength(2));

    api.page = const RemoteTaskPage(
      items: <RemoteTask>[
        RemoteTask(
          id: 'sync:ns:g7',
          kind: RemoteTaskKind.write,
          status: RemoteTaskStatus.done,
        ),
      ],
    );
    await RemoteTaskStore.instance.refresh();
    expect(
      RemoteTaskStore.instance.tasks.any(
        (task) => task.id == 'transfer:metadata-op-old-7',
      ),
      isFalse,
    );
    expect(RemoteTaskStore.instance.tasks, hasLength(1));
  });

  test(
    'reconciles a complete remote page instead of retaining removed rows',
    () async {
      final api = _FakeGateway()
        ..page = const RemoteTaskPage(
          items: <RemoteTask>[
            RemoteTask(
              id: 'sync:ns:keep',
              kind: RemoteTaskKind.upload,
              status: RemoteTaskStatus.done,
            ),
            RemoteTask(
              id: 'sync:ns:remove',
              kind: RemoteTaskKind.upload,
              status: RemoteTaskStatus.done,
            ),
          ],
        );
      RemoteTaskStore.instance.bindApi(api);
      await Future<void>.delayed(Duration.zero);
      api.page = const RemoteTaskPage(
        items: <RemoteTask>[
          RemoteTask(
            id: 'sync:ns:keep',
            kind: RemoteTaskKind.upload,
            status: RemoteTaskStatus.done,
          ),
        ],
      );
      // Complete-snapshot reconciliation only applies to full-history
      // requests now; ask explicitly for the complete set.
      await RemoteTaskStore.instance.refresh(
        const RemoteTaskFilter(includeHistory: true),
      );
      expect(RemoteTaskStore.instance.tasks.map((task) => task.id), [
        'sync:ns:keep',
      ]);
    },
  );

  test(
    'active polling keeps the full history total and queue summary',
    () async {
      final api = _FakeGateway()
        ..page = const RemoteTaskPage(
          items: <RemoteTask>[
            RemoteTask(
              id: 'sync:ns:history-1',
              kind: RemoteTaskKind.download,
              status: RemoteTaskStatus.done,
            ),
            RemoteTask(
              id: 'sync:ns:history-2',
              kind: RemoteTaskKind.download,
              status: RemoteTaskStatus.done,
            ),
          ],
          total: 200,
          hasTotal: true,
          queue: RemoteTaskQueueCounts(
            total: 200,
            history: 200,
            reported: true,
          ),
        );
      RemoteTaskStore.instance.bindApi(api);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(RemoteTaskStore.instance.total, 200);
      expect(RemoteTaskStore.instance.queue.history, 200);
      expect(RemoteTaskStore.instance.tasks, isEmpty);

      await RemoteTaskStore.instance.refresh(
        const RemoteTaskFilter(includeHistory: true),
      );
      expect(RemoteTaskStore.instance.tasks, hasLength(2));

      await RemoteTaskStore.instance.pollActive();
      expect(RemoteTaskStore.instance.total, 200);
      expect(RemoteTaskStore.instance.queue.history, 200);
      expect(RemoteTaskStore.instance.tasks, hasLength(2));
    },
  );

  test('an explicit empty total evicts previously loaded history', () async {
    final api = _FakeGateway()
      ..page = const RemoteTaskPage(
        items: <RemoteTask>[
          RemoteTask(
            id: 'sync:ns:old-history',
            kind: RemoteTaskKind.download,
            status: RemoteTaskStatus.done,
          ),
        ],
        total: 1,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
      );
    RemoteTaskStore.instance.bindApi(api);
    await Future<void>.delayed(Duration.zero);
    await RemoteTaskStore.instance.refresh(
      const RemoteTaskFilter(includeHistory: true),
    );
    expect(RemoteTaskStore.instance.tasks, hasLength(1));

    api.page = const RemoteTaskPage(
      total: 0,
      hasTotal: true,
      queue: RemoteTaskQueueCounts(reported: true),
    );
    await RemoteTaskStore.instance.pollActive();

    expect(RemoteTaskStore.instance.total, 0);
    expect(RemoteTaskStore.instance.queue.total, 0);
    expect(RemoteTaskStore.instance.tasks, isEmpty);
  });

  test('active-only polling leaves retained history loadable', () async {
    final api = _FakeGateway()
      ..page = const RemoteTaskPage(
        items: <RemoteTask>[
          RemoteTask(
            id: 'sync:ns:history',
            kind: RemoteTaskKind.download,
            status: RemoteTaskStatus.done,
          ),
        ],
        total: 1,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
      );
    RemoteTaskStore.instance.bindApi(api);
    await Future<void>.delayed(Duration.zero);

    expect(RemoteTaskStore.instance.tasks, isEmpty);
    expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);

    await RemoteTaskStore.instance.loadMore();

    expect(RemoteTaskStore.instance.tasks, hasLength(1));
    expect(RemoteTaskStore.instance.canLoadMoreHistory, isFalse);
  });

  test('active polling evicts a vanished failed task', () async {
    final api = _FakeGateway()
      ..page = const RemoteTaskPage(
        items: <RemoteTask>[
          RemoteTask(
            id: 'sync:ns:failed',
            kind: RemoteTaskKind.upload,
            status: RemoteTaskStatus.failed,
          ),
        ],
        total: 1,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 1, failed: 1, reported: true),
      );
    RemoteTaskStore.instance.bindApi(api);
    await Future<void>.delayed(Duration.zero);
    expect(RemoteTaskStore.instance.tasks, hasLength(1));

    api.page = const RemoteTaskPage(
      items: <RemoteTask>[
        RemoteTask(
          id: 'sync:ns:running',
          kind: RemoteTaskKind.upload,
          status: RemoteTaskStatus.running,
        ),
      ],
      total: 1,
      hasTotal: true,
      queue: RemoteTaskQueueCounts(total: 1, active: 1, reported: true),
    );
    await RemoteTaskStore.instance.pollActive();

    expect(
      RemoteTaskStore.instance.tasks.map((task) => task.id),
      orderedEquals(<String>['sync:ns:running']),
    );
  });

  test('local lifecycle shortcuts update the registered task', () {
    const id = 'transfer:local-lifecycle';
    RemoteTaskStore.instance.publishLocalTask(
      const RemoteTask(
        id: id,
        kind: RemoteTaskKind.download,
        status: RemoteTaskStatus.running,
        source: RemoteTaskSource.local,
      ),
    );
    expect(RemoteTaskStore.instance.completeLocalTask(id), isTrue);
    expect(
      RemoteTaskStore.instance.localTask(id)?.status,
      RemoteTaskStatus.done,
    );
    expect(RemoteTaskStore.instance.cancelLocalTask('missing'), isFalse);
  });

  test('does not render terminal local producer history without Go rows', () {
    const id = 'transfer:local-terminal';
    RemoteTaskStore.instance.publishLocalTask(
      const RemoteTask(
        id: id,
        kind: RemoteTaskKind.download,
        status: RemoteTaskStatus.done,
        source: RemoteTaskSource.local,
      ),
    );

    expect(RemoteTaskStore.instance.localTask(id), isNotNull);
    expect(RemoteTaskStore.instance.tasks, isEmpty);
  });

  test('sorts mixed-zone task timestamps by their instant', () {
    RemoteTaskStore.instance.publishLocalTask(
      const RemoteTask(
        id: 'transfer:earlier',
        kind: RemoteTaskKind.download,
        status: RemoteTaskStatus.running,
        source: RemoteTaskSource.local,
        updatedAt: '2026-08-24T12:00:00+08:00',
      ),
    );
    RemoteTaskStore.instance.publishLocalTask(
      const RemoteTask(
        id: 'transfer:later',
        kind: RemoteTaskKind.download,
        status: RemoteTaskStatus.running,
        source: RemoteTaskSource.local,
        updatedAt: '2026-08-24T05:00:00Z',
      ),
    );

    expect(
      RemoteTaskStore.instance.tasks.map((task) => task.id),
      orderedEquals(<String>['transfer:later', 'transfer:earlier']),
    );
  });

  test(
    'cancel refuses a task after the provider marks it non-cancelable',
    () async {
      final api = _FakeGateway()
        ..page = const RemoteTaskPage(
          items: <RemoteTask>[
            RemoteTask(
              id: 'transfer:app_update_1',
              kind: RemoteTaskKind.appUpdate,
              status: RemoteTaskStatus.running,
              phaseDetail: 'installing',
              cancelable: false,
            ),
          ],
        );
      RemoteTaskStore.instance.bindApi(api);
      await Future<void>.delayed(Duration.zero);

      expect(
        await RemoteTaskStore.instance.cancel('transfer:app_update_1'),
        isFalse,
      );
      expect(
        RemoteTaskStore.instance.tasks.single.status,
        RemoteTaskStatus.running,
      );
    },
  );

  test('mount reads retain their object path and byte range', () {
    final task = RemoteTask.fromJson(const <String, dynamic>{
      'id': 'transfer:mount-read-1',
      'kind': 'download',
      'status': 'done',
      'sourcePath': 'root/charge.tar',
      'targetPath': 'bytes=1048576-1572863',
      // Older bridge versions sent the detail only through phase.
      'phase': 'mount_read',
    });
    expect(task.isMountRead, isTrue);
    expect(task.operationPath, 'root/charge.tar');
    expect(task.mountReadRange, 'bytes=1048576-1572863');
  });

  test('runtime tasks retain local destination and multipart range', () {
    final task = RemoteTask.fromJson(const <String, dynamic>{
      'id': 'transfer:download-1',
      'kind': 'download',
      'status': 'running',
      'source': 'runtime',
      'sourcePath': 'remote.bin',
      'localPath': '/tmp/remote.bin',
      'phaseDetail': 'downloading',
      'progress': <String, dynamic>{
        'currentKey': 'remote.bin',
        'currentFileBytesCompleted': 4,
        'currentFileTotalBytes': 8,
        'currentRange': 'bytes=0-7',
        'currentPart': 1,
        'totalParts': 4,
      },
    });
    expect(task.localPath, '/tmp/remote.bin');
    expect(task.phaseLabel, '下载中');
    expect(task.progress.currentFileBytesCompleted, 4);
    expect(task.progress.currentRange, 'bytes=0-7');
    expect(task.progress.totalParts, 4);
  });
}

class _FakeGateway extends Fake implements RemoteStorageGateway {
  RemoteTaskPage page = const RemoteTaskPage();
  Object? error;

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async {
    if (error != null) throw error!;
    // Mirror the server contract: active-only requests (history excluded)
    // return only non-terminal rows, so the store's poll/history split can be
    // exercised without a real backend.
    if (!filter.includeHistory) {
      final active = page.items
          .where((task) => !isRemoteTaskHistory(task))
          .toList(growable: false);
      return RemoteTaskPage(
        items: active,
        total: page.total,
        hasTotal: page.hasTotal,
        queue: page.queue,
        nextCursor: page.nextCursor,
        serverTime: page.serverTime,
        freshness: page.freshness,
        capabilities: page.capabilities,
      );
    }
    return page;
  }
}
