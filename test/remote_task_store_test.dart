// RemoteTaskStore tests ensure endpoint failures never resurrect legacy rows.
import 'dart:async';

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

  test(
    'page entry loads the first retained history page automatically',
    () async {
      final api = _FakeGateway()
        ..page = const RemoteTaskPage(
          items: <RemoteTask>[
            RemoteTask(
              id: 'sync:ns:automatic-history',
              kind: RemoteTaskKind.download,
              status: RemoteTaskStatus.done,
            ),
          ],
          total: 1,
          hasTotal: true,
          queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
        );
      RemoteTaskStore.instance.bindApi(api);

      await RemoteTaskStore.instance.loadInitialHistory();

      expect(RemoteTaskStore.instance.tasks, hasLength(1));
      expect(RemoteTaskStore.instance.canLoadMoreHistory, isFalse);
    },
  );

  test('clearing history invalidates an old history cursor', () async {
    const first = RemoteTask(
      id: 'sync:ns:old-cursor-first',
      kind: RemoteTaskKind.download,
      status: RemoteTaskStatus.done,
    );
    const second = RemoteTask(
      id: 'sync:ns:old-cursor-second',
      kind: RemoteTaskKind.download,
      status: RemoteTaskStatus.done,
    );
    final api = _FakeGateway()
      ..page = const RemoteTaskPage(
        items: <RemoteTask>[first],
        total: 2,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 2, history: 2, reported: true),
        nextCursor: 'history:next',
      )
      ..continuationPage = const RemoteTaskPage(
        items: <RemoteTask>[second],
        total: 2,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 2, history: 2, reported: true),
      );
    RemoteTaskStore.instance.bindApi(api);

    await RemoteTaskStore.instance.loadMore();
    expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);

    await RemoteTaskStore.instance.clearHistory(taskIds: <String>[first.id]);

    expect(RemoteTaskStore.instance.nextCursor, isEmpty);
    expect(RemoteTaskStore.instance.canLoadMoreHistory, isFalse);
  });

  test('active polling cannot overlap an in-flight history page', () async {
    final api = _FakeGateway()
      ..page = const RemoteTaskPage(
        total: 2,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 2, history: 2, reported: true),
      );
    RemoteTaskStore.instance.bindApi(api);
    await Future<void>.delayed(Duration.zero);
    api.pendingHistory = Completer<RemoteTaskPage>();

    final firstHistoryPage = RemoteTaskStore.instance.loadMore();
    await Future<void>.delayed(Duration.zero);
    expect(api.historyRequests, 1);

    // Joining callers must not start a second request while the first history
    // page owns the serialized read gate.
    unawaited(RemoteTaskStore.instance.pollActive());
    expect(api.activeRequests, 1);
    expect(api.historyRequests, 1);

    api.pendingHistory!.complete(
      const RemoteTaskPage(
        total: 2,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 2, history: 2, reported: true),
        nextCursor: 'history:next',
      ),
    );
    await firstHistoryPage;
    expect(RemoteTaskStore.instance.nextCursor, 'history:next');
  });

  test('page entry waits for another refresh before loading history', () async {
    const retained = RemoteTask(
      id: 'sync:ns:joined-history',
      kind: RemoteTaskKind.download,
      status: RemoteTaskStatus.done,
    );
    final api = _FakeGateway()
      ..page = const RemoteTaskPage(
        items: <RemoteTask>[retained],
        total: 1,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
      );
    RemoteTaskStore.instance.bindApi(api);
    await Future<void>.delayed(Duration.zero);
    api.pendingActive = Completer<RemoteTaskPage>();

    final otherRefresh = RemoteTaskStore.instance.refresh(
      const RemoteTaskFilter(includeHistory: false),
    );
    await Future<void>.delayed(Duration.zero);
    final pageEntry = RemoteTaskStore.instance.loadInitialHistory();
    expect(api.historyRequests, 0);

    api.pendingActive!.complete(
      const RemoteTaskPage(
        total: 1,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
      ),
    );
    await otherRefresh;
    await pageEntry;

    expect(api.historyRequests, 1);
    expect(RemoteTaskStore.instance.tasks.single.id, retained.id);
  });

  test(
    'initial history page is compact and keeps the next page reachable',
    () async {
      final api = _PagingGateway(activeCount: 1, historyCount: 500);
      RemoteTaskStore.instance.bindApi(api);

      await RemoteTaskStore.instance.loadInitialHistory();

      expect(
        RemoteTaskStore.instance.tasks.where(isRemoteTaskHistory),
        hasLength(100),
      );
      expect(RemoteTaskStore.instance.loadedHistoryCount, 100);
      expect(RemoteTaskStore.instance.historyTotal, 500);
      expect(RemoteTaskStore.instance.remainingHistoryCount, 400);
      expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);
      expect(api.historyLimits, <int>[100, 1]);
    },
  );

  test(
    'loading the next history page advances the visible history count',
    () async {
      final api = _PagingGateway(activeCount: 0, historyCount: 150);
      RemoteTaskStore.instance.bindApi(api);

      await RemoteTaskStore.instance.loadInitialHistory();
      expect(RemoteTaskStore.instance.loadedHistoryCount, 100);
      expect(RemoteTaskStore.instance.remainingHistoryCount, 50);

      await RemoteTaskStore.instance.loadMore();
      expect(RemoteTaskStore.instance.loadedHistoryCount, 150);
      expect(RemoteTaskStore.instance.remainingHistoryCount, 0);
      expect(RemoteTaskStore.instance.canLoadMoreHistory, isFalse);
      expect(api.historyLimits, <int>[100, 100]);
    },
  );

  test(
    'each new terminal task invalidates a stale exhausted history cursor',
    () async {
      final api = _PagingGateway(activeCount: 0, historyCount: 150);
      RemoteTaskStore.instance.bindApi(api);

      await RemoteTaskStore.instance.loadInitialHistory();
      await RemoteTaskStore.instance.loadMore();
      expect(RemoteTaskStore.instance.canLoadMoreHistory, isFalse);

      api.addHistory('sync:paging:history-new');
      await RemoteTaskStore.instance.pollActive();

      expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);
      await RemoteTaskStore.instance.loadMore();
      expect(
        RemoteTaskStore.instance.tasks.map((task) => task.id),
        contains('sync:paging:history-new'),
      );
      expect(RemoteTaskStore.instance.canLoadMoreHistory, isFalse);

      api.addHistory('sync:paging:history-newer');
      await RemoteTaskStore.instance.pollActive();

      expect(RemoteTaskStore.instance.nextCursor, isEmpty);
      expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);
      await RemoteTaskStore.instance.loadMore();
      expect(
        RemoteTaskStore.instance.tasks.map((task) => task.id),
        contains('sync:paging:history-newer'),
      );
      expect(RemoteTaskStore.instance.canLoadMoreHistory, isFalse);
    },
  );

  test(
    'initial history load keeps its first page bounded when history grows',
    () async {
      final api = _PagingGateway(activeCount: 0, historyCount: 100);
      RemoteTaskStore.instance.bindApi(api);
      await RemoteTaskStore.instance.pollActive();
      api.addHistoryDuringNextInitialPage('sync:paging:history-initial-race');

      await RemoteTaskStore.instance.loadInitialHistory();

      expect(RemoteTaskStore.instance.isLoadingInitialHistory, isFalse);
      expect(
        RemoteTaskStore.instance.tasks.where(isRemoteTaskHistory),
        hasLength(100),
      );
      expect(RemoteTaskStore.instance.historyTotal, 101);
      expect(RemoteTaskStore.instance.remainingHistoryCount, 1);
      expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);
      expect(
        RemoteTaskStore.instance.tasks.map((task) => task.id),
        contains('sync:paging:history-initial-race'),
      );
    },
  );

  test('continuation retries through repeated terminal completions', () async {
    final api = _PagingGateway(activeCount: 0, historyCount: 150);
    RemoteTaskStore.instance.bindApi(api);

    await RemoteTaskStore.instance.loadInitialHistory();
    expect(RemoteTaskStore.instance.nextCursor, '100');
    api.addHistoryDuringNextContinuation('sync:paging:history-race');
    api.addHistoryDuringNextInitialPage('sync:paging:history-race-newer');

    await RemoteTaskStore.instance.loadMore();

    expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);
    expect(
      RemoteTaskStore.instance.tasks.map((task) => task.id),
      contains('sync:paging:history-race'),
    );
    expect(
      RemoteTaskStore.instance.tasks.map((task) => task.id),
      contains('sync:paging:history-race-newer'),
    );
  });

  test('history pagination yields after continual cursor shifts', () async {
    final api = _PagingGateway(activeCount: 0, historyCount: 150);
    RemoteTaskStore.instance.bindApi(api);
    await RemoteTaskStore.instance.loadInitialHistory();
    api.addHistoryDuringHistoryRequests(<String>[
      'sync:paging:history-busy-one',
      'sync:paging:history-busy-two',
    ]);

    await RemoteTaskStore.instance.loadMore().timeout(
      const Duration(seconds: 1),
    );

    expect(RemoteTaskStore.instance.isLoadingMoreHistory, isFalse);
    expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);
  });

  test(
    'initial history loading yields while the queue keeps changing',
    () async {
      final api = _PagingGateway(activeCount: 16, historyCount: 150);
      RemoteTaskStore.instance.bindApi(api);
      await RemoteTaskStore.instance.pollActive();
      api.addHistoryDuringHistoryRequests(<String>[
        'sync:paging:initial-busy-one',
        'sync:paging:initial-busy-two',
      ]);

      await RemoteTaskStore.instance.loadInitialHistory().timeout(
        const Duration(seconds: 1),
      );

      expect(RemoteTaskStore.instance.isLoadingInitialHistory, isFalse);
      expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);
    },
  );

  test('a failed first history page remains retryable', () async {
    const retained = RemoteTask(
      id: 'sync:ns:retry-history',
      kind: RemoteTaskKind.download,
      status: RemoteTaskStatus.done,
    );
    final api = _FakeGateway()
      ..page = const RemoteTaskPage(
        items: <RemoteTask>[retained],
        total: 1,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
      );
    RemoteTaskStore.instance.bindApi(api);
    await Future<void>.delayed(Duration.zero);
    api.historyError = StateError('history offline');

    await RemoteTaskStore.instance.loadInitialHistory();
    expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);

    api.historyError = null;
    await RemoteTaskStore.instance.pollActive();
    expect(RemoteTaskStore.instance.canLoadMoreHistory, isTrue);
    await RemoteTaskStore.instance.loadInitialHistory();

    expect(RemoteTaskStore.instance.tasks.single.id, retained.id);
  });

  test(
    'clearing history ignores an already in-flight history response',
    () async {
      const retained = RemoteTask(
        id: 'sync:ns:stale-clear-history',
        kind: RemoteTaskKind.download,
        status: RemoteTaskStatus.done,
      );
      final api = _FakeGateway()
        ..page = const RemoteTaskPage(
          items: <RemoteTask>[retained],
          total: 1,
          hasTotal: true,
          queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
        );
      RemoteTaskStore.instance.bindApi(api);
      await Future<void>.delayed(Duration.zero);
      api.pendingHistory = Completer<RemoteTaskPage>();
      final historyPage = RemoteTaskStore.instance.loadMore();
      await Future<void>.delayed(Duration.zero);

      final clear = RemoteTaskStore.instance.clearHistory(
        taskIds: <String>[retained.id],
      );
      api.pendingHistory!.complete(
        const RemoteTaskPage(
          items: <RemoteTask>[retained],
          total: 1,
          hasTotal: true,
          queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
          nextCursor: 'stale-cursor',
        ),
      );
      await historyPage;
      await clear;

      expect(RemoteTaskStore.instance.tasks, isEmpty);
      expect(RemoteTaskStore.instance.nextCursor, isEmpty);
    },
  );

  test('a late clear from a previous API cannot erase a new binding', () async {
    const oldTask = RemoteTask(
      id: 'sync:old:history',
      kind: RemoteTaskKind.download,
      status: RemoteTaskStatus.done,
    );
    const newTask = RemoteTask(
      id: 'sync:new:history',
      kind: RemoteTaskKind.download,
      status: RemoteTaskStatus.done,
    );
    final oldApi = _FakeGateway()
      ..page = const RemoteTaskPage(
        items: <RemoteTask>[oldTask],
        total: 1,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
      )
      ..pendingClear = Completer<int>();
    RemoteTaskStore.instance.bindApi(oldApi);
    await RemoteTaskStore.instance.loadMore();
    final clear = RemoteTaskStore.instance.clearHistory(
      taskIds: <String>[oldTask.id],
    );
    await Future<void>.delayed(Duration.zero);

    final newApi = _FakeGateway()
      ..page = const RemoteTaskPage(
        items: <RemoteTask>[newTask],
        total: 1,
        hasTotal: true,
        queue: RemoteTaskQueueCounts(total: 1, history: 1, reported: true),
      );
    RemoteTaskStore.instance.bindApi(newApi);
    await RemoteTaskStore.instance.loadInitialHistory();
    oldApi.pendingClear!.complete(1);

    expect(await clear, 0);
    expect(RemoteTaskStore.instance.tasks.single.id, newTask.id);
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
  RemoteTaskPage? continuationPage;
  Completer<RemoteTaskPage>? pendingHistory;
  Completer<RemoteTaskPage>? pendingActive;
  Completer<int>? pendingClear;
  int activeRequests = 0;
  int historyRequests = 0;
  Object? error;
  Object? historyError;

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async {
    if (error != null) throw error!;
    if (filter.includeHistory) {
      historyRequests++;
      if (historyError != null) throw historyError!;
      final pending = pendingHistory;
      if (pending != null) return pending.future;
    } else {
      activeRequests++;
      final pending = pendingActive;
      if (pending != null) return pending.future;
    }
    final response = filter.includeHistory && filter.cursor.isNotEmpty
        ? continuationPage ?? page
        : page;
    // Mirror the server contract: active-only requests (history excluded)
    // return only non-terminal rows, so the store's poll/history split can be
    // exercised without a real backend.
    if (!filter.includeHistory) {
      final active = response.items
          .where((task) => !isRemoteTaskHistory(task))
          .toList(growable: false);
      return RemoteTaskPage(
        items: active,
        total: response.total,
        hasTotal: response.hasTotal,
        queue: response.queue,
        serverTime: response.serverTime,
        freshness: response.freshness,
        capabilities: response.capabilities,
      );
    }
    return response;
  }

  @override
  Future<int> clearRemoteTaskHistory({
    String profileId = '',
    String bucket = '',
    List<String> taskIds = const <String>[],
  }) async {
    final pending = pendingClear;
    if (pending != null) return pending.future;
    final removed = taskIds.isEmpty ? page.items.length : taskIds.length;
    page = const RemoteTaskPage(
      total: 0,
      hasTotal: true,
      queue: RemoteTaskQueueCounts(reported: true),
    );
    continuationPage = null;
    return removed;
  }
}

// Models the shared server ordering: every active row precedes retained
// history, and cursors/limits apply to that combined ordered stream.
class _PagingGateway extends Fake implements RemoteStorageGateway {
  _PagingGateway({required int activeCount, required int historyCount})
    : _items = <RemoteTask>[
        for (var index = 0; index < activeCount; index++)
          RemoteTask(
            id: 'sync:paging:active-$index',
            kind: RemoteTaskKind.download,
            status: RemoteTaskStatus.running,
          ),
        for (var index = 0; index < historyCount; index++)
          RemoteTask(
            id: 'sync:paging:history-$index',
            kind: RemoteTaskKind.download,
            status: RemoteTaskStatus.done,
          ),
      ],
      _activeCount = activeCount,
      _historyCount = historyCount;

  final List<RemoteTask> _items;
  final int _activeCount;
  int _historyCount;
  final List<int> historyLimits = <int>[];
  final List<String> _historyToAddDuringRequests = <String>[];
  String? _historyToAddDuringInitialPage;
  String? _historyToAddDuringContinuation;

  void addHistory(String id) {
    _items.insert(
      _activeCount,
      RemoteTask(
        id: id,
        kind: RemoteTaskKind.download,
        status: RemoteTaskStatus.done,
      ),
    );
    _historyCount++;
  }

  void addHistoryDuringNextContinuation(String id) {
    _historyToAddDuringContinuation = id;
  }

  void addHistoryDuringNextInitialPage(String id) {
    _historyToAddDuringInitialPage = id;
  }

  void addHistoryDuringHistoryRequests(Iterable<String> ids) {
    _historyToAddDuringRequests.addAll(ids);
  }

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async {
    if (filter.includeHistory && _historyToAddDuringRequests.isNotEmpty) {
      addHistory(_historyToAddDuringRequests.removeAt(0));
    }
    if (filter.includeHistory &&
        filter.cursor.isEmpty &&
        _historyToAddDuringInitialPage != null) {
      final id = _historyToAddDuringInitialPage!;
      _historyToAddDuringInitialPage = null;
      addHistory(id);
    }
    if (filter.includeHistory &&
        filter.cursor.isNotEmpty &&
        _historyToAddDuringContinuation != null) {
      final id = _historyToAddDuringContinuation!;
      _historyToAddDuringContinuation = null;
      addHistory(id);
    }
    final queue = RemoteTaskQueueCounts(
      active: _activeCount,
      history: _historyCount,
      total: _items.length,
      reported: true,
    );
    if (!filter.includeHistory) {
      return RemoteTaskPage(
        items: _items.take(_activeCount).toList(growable: false),
        total: _items.length,
        hasTotal: true,
        queue: queue,
      );
    }
    historyLimits.add(filter.limit);
    final offset = int.tryParse(filter.cursor) ?? 0;
    final page = _items.skip(offset).take(filter.limit).toList(growable: false);
    final nextOffset = offset + page.length;
    return RemoteTaskPage(
      items: page,
      total: _items.length,
      hasTotal: true,
      queue: queue,
      nextCursor: nextOffset < _items.length ? '$nextOffset' : '',
    );
  }
}
