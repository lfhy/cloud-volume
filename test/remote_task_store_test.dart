// RemoteTaskStore tests ensure endpoint failures never resurrect legacy rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_task.dart';
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
      await RemoteTaskStore.instance.refresh();
      expect(RemoteTaskStore.instance.tasks.map((task) => task.id), [
        'sync:ns:keep',
      ]);
    },
  );

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
}

class _FakeGateway extends Fake implements RemoteStorageGateway {
  RemoteTaskPage page = const RemoteTaskPage();
  Object? error;

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async {
    if (error != null) throw error!;
    return page;
  }
}
