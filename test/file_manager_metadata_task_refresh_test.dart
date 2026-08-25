// Metadata task refresh tests ensure a completed mkdir reloads its remote mtime.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  setUp(RemoteTaskStore.instance.resetForTest);
  tearDown(RemoteTaskStore.instance.resetForTest);

  testWidgets('completed metadata mkdir reloads the current directory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _MetadataCreateApi();
    RemoteTaskStore.instance.bindApi(api);
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: FileManagerPage(
            api: api,
            config: RemoteStorageConfig.empty().copyWith(
              profileId: _MetadataCreateApi.profileID,
            ),
            profiles: const [],
            onRefresh: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_MetadataCreateApi.bucket));
    await tester.pumpAndSettle();
    final browser = tester.widget<FileManagerObjectBrowser>(
      find.byType(FileManagerObjectBrowser),
    );
    browser.onCreateDirectory!();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'docs');
    await tester.tap(find.widgetWithText(ShadButton, '创建'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.forceRefreshCount, greaterThanOrEqualTo(1));
    expect(
      tester
          .widget<FileManagerObjectBrowser>(
            find.byType(FileManagerObjectBrowser),
          )
          .objects
          .single
          .lastModified,
      isEmpty,
    );

    api.completeDirectory();
    await RemoteTaskStore.instance.refresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final refreshed = tester.widget<FileManagerObjectBrowser>(
      find.byType(FileManagerObjectBrowser),
    );
    expect(api.forceRefreshCount, greaterThanOrEqualTo(2));
    expect(
      refreshed.objects.single.lastModified,
      _MetadataCreateApi.remoteMTime,
    );

    RemoteTaskStore.instance.resetForTest();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _MetadataCreateApi implements RemoteStorageGateway {
  static const bucket = 'bucket-a';
  static const profileID = 'profile-a';
  static const remoteMTime = '2026-08-19 10:15:30';

  List<ObjectInfo> _objects = const <ObjectInfo>[];
  RemoteTaskPage _taskPage = const RemoteTaskPage();
  int forceRefreshCount = 0;

  @override
  RemoteStorageCapabilities get capabilities =>
      const RemoteStorageCapabilities.desktop();

  @override
  Future<List<BucketInfo>> listBuckets(
    RemoteStorageConfig config, {
    bool force = false,
  }) async => const <BucketInfo>[BucketInfo(name: bucket)];

  @override
  Future<BucketInfo> getBucketQuota(
    RemoteStorageConfig config,
    String value,
  ) async => BucketInfo(name: value);

  @override
  Future<List<String>> listBucketOrder() async => const <String>[];

  @override
  Future<ObjectListPage> listObjectPage(
    RemoteStorageConfig config,
    String value,
    String prefix,
    String nextToken,
    int pageSize, {
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) forceRefreshCount++;
    return ObjectListPage(items: _objects, nextToken: '');
  }

  @override
  Future<DirectoryAccess> directoryAccess(
    RemoteStorageConfig config,
    String value,
    String prefix,
  ) async => const DirectoryAccess(writable: true, known: true);

  @override
  Future<void> createDirectory(
    RemoteStorageConfig config,
    String value,
    String prefix,
    String name,
  ) async {
    final createdAt = DateTime.now().toUtc().toIso8601String();
    _objects = const <ObjectInfo>[
      ObjectInfo(key: 'docs/', size: 0, lastModified: '', isDir: true),
    ];
    _taskPage = RemoteTaskPage(
      items: <RemoteTask>[
        RemoteTask(
          id: 'sync:namespace:gmkdir',
          kind: RemoteTaskKind.mkdir,
          status: RemoteTaskStatus.waiting,
          source: RemoteTaskSource.metadata,
          bucket: bucket,
          profileId: profileID,
          targetPath: 'docs',
          displayPath: 'docs',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
    );
  }

  void completeDirectory() {
    final now = DateTime.now().toUtc().toIso8601String();
    _objects = const <ObjectInfo>[
      ObjectInfo(key: 'docs/', size: 0, lastModified: remoteMTime, isDir: true),
    ];
    _taskPage = RemoteTaskPage(
      items: <RemoteTask>[
        RemoteTask(
          id: 'sync:namespace:gmkdir',
          kind: RemoteTaskKind.mkdir,
          status: RemoteTaskStatus.done,
          source: RemoteTaskSource.metadata,
          bucket: bucket,
          profileId: profileID,
          targetPath: 'docs',
          displayPath: 'docs',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async => _taskPage;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
