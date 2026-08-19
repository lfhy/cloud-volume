// Object-browser sync badge tests pin mkdir/rename/delete task coverage and
// profile scoping so a freshly created directory reports its pending state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  setUp(RemoteTaskStore.instance.resetForTest);
  tearDown(RemoteTaskStore.instance.resetForTest);

  testWidgets('mkdir task marks the new directory as pending until done', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    RemoteTaskStore.instance.publishLocalTask(
      const RemoteTask(
        id: 'sync:ns:g1',
        kind: RemoteTaskKind.mkdir,
        status: RemoteTaskStatus.waiting,
        source: RemoteTaskSource.metadata,
        bucket: 'bucket-a',
        profileId: 'profile-a',
        targetPath: 'docs',
      ),
    );

    await tester.pumpWidget(
      ShadApp(
        home: Material(
          child: FileManagerObjectBrowser(
            objects: const [
              ObjectInfo(key: 'docs/', size: 0, isDir: true),
              ObjectInfo(key: 'notes.txt', size: 3, isDir: false),
            ],
            prefix: '',
            isGrid: false,
            scrollController: ScrollController(),
            hasMore: false,
            loadingMore: false,
            selectedKeys: const <String>{},
            deletingKeys: const <String>{},
            gridIconSize: 44,
            listIconSize: 34,
            mountedToDesktop: true,
            mountBucketName: 'bucket-a',
            profileId: 'profile-a',
            showSyncStatus: true,
            onOpenDirectory: (_) {},
            onOpenFile: (_) {},
            onDownloadFile: (_) {},
            onNavigateUp: () {},
            onToggleSelection: (_) {},
            onSelectionSetChanged: (_) {},
            onToggleSelectAll: () {},
            onObjectAction: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('等待同步'), findsOneWidget);
    expect(find.text('已同步'), findsOneWidget);

    RemoteTaskStore.instance.publishLocalTask(
      const RemoteTask(
        id: 'sync:ns:g1',
        kind: RemoteTaskKind.mkdir,
        status: RemoteTaskStatus.done,
        source: RemoteTaskSource.metadata,
        bucket: 'bucket-a',
        profileId: 'profile-a',
        targetPath: 'docs',
      ),
    );
    await tester.pump();

    expect(find.text('等待同步'), findsNothing);
    expect(find.text('已同步'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tasks from another profile do not affect badges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    RemoteTaskStore.instance.publishLocalTask(
      const RemoteTask(
        id: 'sync:other:g1',
        kind: RemoteTaskKind.rename,
        status: RemoteTaskStatus.running,
        source: RemoteTaskSource.metadata,
        bucket: 'bucket-a',
        profileId: 'profile-other',
        targetPath: 'docs',
      ),
    );

    await tester.pumpWidget(
      ShadApp(
        home: Material(
          child: FileManagerObjectBrowser(
            objects: const [ObjectInfo(key: 'docs/', size: 0, isDir: true)],
            prefix: '',
            isGrid: false,
            scrollController: ScrollController(),
            hasMore: false,
            loadingMore: false,
            selectedKeys: const <String>{},
            deletingKeys: const <String>{},
            gridIconSize: 44,
            listIconSize: 34,
            mountedToDesktop: true,
            mountBucketName: 'bucket-a',
            profileId: 'profile-a',
            showSyncStatus: true,
            onOpenDirectory: (_) {},
            onOpenFile: (_) {},
            onDownloadFile: (_) {},
            onNavigateUp: () {},
            onToggleSelection: (_) {},
            onSelectionSetChanged: (_) {},
            onToggleSelectAll: () {},
            onObjectAction: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('同步中'), findsNothing);
    expect(find.text('已同步'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
