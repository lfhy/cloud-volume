// Update service tests keep local and GitHub release version comparisons stable.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/services/app_update_service.dart';
import 'package:remote_storage/services/update_settings.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/widgets/settings_update_task_policy.dart';

void main() {
  test('release API check uses a longer timeout budget', () {
    expect(kAppReleaseApiTimeout.inSeconds, 30);
    expect(kAppReleaseApiMaxAttempts, 3);
  });

  test('TransferTask maps app_update kind to appUpdate', () {
    final task = TransferTask.fromJson(const {
      'id': 'app_update_1',
      'kind': 'app_update',
      'rawType': 'app_update',
      'title': 'app_update',
    });
    expect(task.kind, TransferKind.appUpdate);
    expect(task.typeLabel, '应用更新');
  });

  test('isActiveFileTransfer excludes app update', () {
    final upload = TransferTask.fromJson(const {
      'id': 'u1',
      'kind': 'upload',
      'status': 'running',
    });
    final update = TransferTask.fromJson(const {
      'id': 'app_update_1',
      'kind': 'app_update',
      'status': 'running',
    });
    expect(upload.isActiveFileTransfer, isTrue);
    expect(update.isActiveFileTransfer, isFalse);
  });

  test('metadata-backed producer flag survives task persistence', () {
    final task = TransferTask.fromJson(const {
      'id': 'page-move',
      'kind': 'move',
      'publishRemoteTask': false,
    });
    expect(task.publishRemoteTask, isFalse);
    expect(task.toJson()['publishRemoteTask'], isFalse);
  });

  test('app update cancellation stops at the installer boundary', () {
    const installing = RemoteTask(
      id: 'transfer:app_update_1',
      kind: RemoteTaskKind.appUpdate,
      status: RemoteTaskStatus.running,
      phaseDetail: 'installing',
      cancelable: false,
    );
    expect(
      canCancelAppUpdate(
        installing: true,
        taskId: 'app_update_1',
        tasks: const [installing],
      ),
      isFalse,
    );
    expect(
      canCancelAppUpdate(
        installing: true,
        taskId: 'missing',
        tasks: const <RemoteTask>[],
      ),
      isFalse,
    );
    expect(
      canCancelAppUpdate(
        installing: true,
        taskId: null,
        tasks: const <RemoteTask>[],
      ),
      isTrue,
    );
  });

  test('compareVersionLabels detects newer GitHub release tags', () {
    expect(compareVersionLabels('v1.2.2', 'v1.2.3'), lessThan(0));
    expect(compareVersionLabels('1.2.3+7', 'v1.2.3'), 0);
    expect(compareVersionLabels('1.3.0', 'v1.2.9'), greaterThan(0));
  });

  test('compareVersionLabels handles prerelease ordering', () {
    expect(compareVersionLabels('v1.2.3-beta.1', 'v1.2.3'), lessThan(0));
    expect(
      compareVersionLabels('v1.2.3-beta.2', 'v1.2.3-beta.1'),
      greaterThan(0),
    );
  });

  test('compareVersionLabels returns null for dev builds', () {
    expect(compareVersionLabels('dev', 'v1.2.3'), isNull);
  });

  test('UpdateNetworkConfig persists and reloads mirror prefix', () async {
    SharedPreferences.setMockInitialValues({
      kUpdateMirrorKey: 'https://gh-proxy.com',
    });
    final loaded = await loadUpdateNetworkConfig();
    expect(loaded.mirrorPrefix, 'https://gh-proxy.com');
    expect(loaded.hasMirror, isTrue);
    expect(
      loaded.wrapUrl('https://github.com/a/b'),
      'https://gh-proxy.com/https://github.com/a/b',
    );

    await saveUpdateNetworkConfig(const UpdateNetworkConfig(mirrorPrefix: ''));
    final reloaded = await loadUpdateNetworkConfig();
    expect(reloaded.mirrorPrefix, isEmpty);
    expect(reloaded.hasMirror, isFalse);
  });
}
