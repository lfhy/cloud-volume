// Widget tests verify the app boots and shows the Chinese bootstrap UI.

import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/app/remote_storage_app.dart';
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/services/sync_directory_navigation.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/sidebar_item.dart';
import 'package:remote_storage/models/sync_remote_open_request.dart';
import 'package:remote_storage/models/system_proxy_info.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/pages/main_layout_page.dart';
import 'package:remote_storage/pages/mobile_file_manager_page.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/state/object_listing_notifier.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/widgets/file_manager_breadcrumb_bar.dart';
import 'package:remote_storage/widgets/file_manager_action_bar.dart';
import 'package:remote_storage/widgets/mobile_file_manager_surface.dart';
import 'package:remote_storage/widgets/mobile_file_manager_browser.dart';
import 'package:remote_storage/widgets/mobile_navigation_bar.dart';

void main() {
  setUp(() {
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  tearDown(() {
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  testWidgets('App shows setup page when config is missing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('添加存储账号'), findsOneWidget);
    expect(find.text('S3 对象存储'), findsOneWidget);
    expect(find.text('WebDAV'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  testWidgets('Setup page advances to WebDAV account form', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      RemoteStorageApp(apiFactory: () async => _FakeApi(configured: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下一步'));
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('添加 WebDAV 账号'), findsOneWidget);
    expect(find.text('WebDAV 地址'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('确认添加'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    TransferQueue.instance.resetForTest();
    RemoteTaskStore.instance.resetForTest();
    SyncProfileNotifier.instance.stop();
  });

  testWidgets('App shows main layout when config exists', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        RemoteStorageApp(apiFactory: () async => _FakeApi(configured: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FileManagerPage), findsOneWidget);
      expect(find.byType(MobileFileManagerPage), findsNothing);
      expect(find.byType(MobileFileManagerSurface), findsNothing);
      expect(find.byType(FileManagerActionBar), findsOneWidget);
      expect(find.byType(FileManagerBreadcrumbBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Desktop sync remote open keeps the latest target when an older listing finishes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        SharedPreferences.setMockInitialValues({});
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '桌面文件')],
        );
        final pendingA = Completer<ObjectListPage>();
        final pendingB = Completer<ObjectListPage>();
        api.nextObjectPagesByPrefix['A/'] = pendingA;
        api.nextObjectPagesByPrefix['B/'] = pendingB;

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        expect(find.byType(FileManagerPage), findsOneWidget);

        SyncDirectoryNavigation.instance.openRemote(
          const SyncRemoteOpenRequest(
            profileName: '',
            bucket: '桌面文件',
            remotePrefix: 'A',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(api.objectPagePrefixes, contains('A/'));

        SyncDirectoryNavigation.instance.openRemote(
          const SyncRemoteOpenRequest(
            profileName: '',
            bucket: '桌面文件',
            remotePrefix: 'B',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(api.objectPagePrefixes, contains('B/'));

        // B wins even though its request started after A.
        pendingB.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'B/B-latest.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('B-latest.txt'), findsOneWidget);
        expect(find.text('A-stale.txt'), findsNothing);

        // A finishes late and must not overwrite B's visible directory.
        pendingA.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'A/A-stale.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('B-latest.txt'), findsOneWidget);
        expect(find.text('A-stale.txt'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Desktop sync cancellation restores the prior listing after an in-flight target',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        SharedPreferences.setMockInitialValues({});
        final pendingA = Completer<ObjectListPage>();
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '桌面文件')],
          objectPagesByPrefix: const <String, ObjectListPage>{
            '': ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(
                  key: '原目录.txt',
                  size: 24,
                  lastModified: '2026-08-31',
                  isDir: false,
                ),
              ],
              nextToken: '',
            ),
          },
        );
        api.nextObjectPagesByPrefix['A/'] = pendingA;

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('桌面文件'));
        await tester.pumpAndSettle();
        expect(find.text('原目录.txt'), findsOneWidget);

        SyncDirectoryNavigation.instance.openRemote(
          const SyncRemoteOpenRequest(
            profileName: '',
            bucket: '桌面文件',
            remotePrefix: 'A',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(api.objectPagePrefixes, contains('A/'));
        expect(find.text('加载中...'), findsOneWidget);

        // A direct sidebar choice cancels the shell ticket before its late
        // directory response may change the desktop file-manager state.
        await tester.tap(find.text('账号管理').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('文件管理').first);
        await tester.pumpAndSettle();
        expect(find.text('原目录.txt'), findsOneWidget);
        expect(find.text('加载中...'), findsNothing);

        pendingA.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'A/迟到响应.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('原目录.txt'), findsOneWidget);
        expect(find.text('迟到响应.txt'), findsNothing);
        expect(find.text('加载中...'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Desktop missing replacement target restores the prior listing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({});
      final pendingA = Completer<ObjectListPage>();
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '桌面文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '原目录.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );
      api.nextObjectPagesByPrefix['A/'] = pendingA;

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('桌面文件'));
      await tester.pumpAndSettle();
      expect(find.text('原目录.txt'), findsOneWidget);

      SyncDirectoryNavigation.instance.openRemote(
        const SyncRemoteOpenRequest(
          profileName: '',
          bucket: '桌面文件',
          remotePrefix: 'A',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(api.objectPagePrefixes, contains('A/'));
      expect(find.text('加载中...'), findsOneWidget);

      // The replacement owns the ticket but cannot resolve a bucket. It
      // must restore the snapshot captured before A started loading.
      SyncDirectoryNavigation.instance.openRemote(
        const SyncRemoteOpenRequest(
          profileName: '',
          bucket: '不存在的桌面文件',
          remotePrefix: 'B',
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('原目录.txt'), findsOneWidget);
      expect(find.text('加载中...'), findsNothing);

      pendingA.complete(
        const ObjectListPage(
          items: <ObjectInfo>[
            ObjectInfo(
              key: 'A/迟到响应.txt',
              size: 24,
              lastModified: '2026-08-31',
              isDir: false,
            ),
          ],
          nextToken: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('原目录.txt'), findsOneWidget);
      expect(find.text('迟到响应.txt'), findsNothing);
      expect(find.text('加载中...'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Desktop sync cancellation finishes an initially loading bucket recovery',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final initialBuckets = Completer<List<BucketInfo>>();
      final recoveryBuckets = Completer<List<BucketInfo>>();
      final pendingA = Completer<ObjectListPage>();
      try {
        SharedPreferences.setMockInitialValues({});
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '桌面文件')],
        );
        api.nextObjectPagesByPrefix['A/'] = pendingA;

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();

        // Trigger the file manager's own slow bucket refresh only after all
        // hidden IndexedStack pages have settled, so this queue entry belongs
        // to the visible file page rather than a background page.
        final settledBucketRequests = api.bucketListingRequestCount;
        api.nextBucketListings.add(initialBuckets);
        tester
            .widget<FileManagerBreadcrumbBar>(
              find.byType(FileManagerBreadcrumbBar),
            )
            .onOpenBucketList();
        await tester.pump();
        final initialBucketRequests = api.bucketListingRequestCount;
        expect(initialBucketRequests, greaterThan(settledBucketRequests));
        expect(find.text('加载存储桶...'), findsOneWidget);

        // The existing bucket lets A start its object request immediately,
        // while the still-pending primary refresh makes the desktop snapshot
        // record loading=true rather than an already-rendered directory.
        SyncDirectoryNavigation.instance.openRemote(
          const SyncRemoteOpenRequest(
            profileName: '',
            bucket: '桌面文件',
            remotePrefix: 'A',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(api.objectPagePrefixes, contains('A/'));
        expect(find.text('加载中...'), findsOneWidget);

        api.nextBucketListings.add(recoveryBuckets);
        // Re-selecting the active desktop item cancels the shell ticket while
        // leaving FileManager mounted. Unlike switching to account management,
        // no hidden IndexedStack page can consume this recovery FIFO entry.
        await tester.tap(find.text('文件管理').first);
        // Do not settle while the recovery is deliberately pending: settling
        // advances the fake clock through BucketSourceService's 40s timeout.
        await tester.pump();
        await tester.pump();
        expect(
          api.bucketListingRequestCount,
          greaterThan(initialBucketRequests),
        );

        // The current bucket request remains the recovery path for the
        // loading snapshot. Completing it must clear loading before the user
        // returns to the desktop file page.
        recoveryBuckets.complete(const <BucketInfo>[BucketInfo(name: '桌面文件')]);
        await tester.pumpAndSettle();

        expect(find.text('加载存储桶...'), findsNothing);
        expect(find.text('加载中...'), findsNothing);
        expect(find.text('桌面文件'), findsOneWidget);
        expect(api.objectPagePrefixes, contains('A/'));

        // The pre-sync bucket and object responses are still in flight. They
        // cannot replace the recovery listing after completing late.
        initialBuckets.complete(const <BucketInfo>[BucketInfo(name: '初始迟到桶')]);
        pendingA.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'A/迟到响应.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('桌面文件'), findsOneWidget);
        expect(find.text('初始迟到桶'), findsNothing);
        expect(find.text('迟到响应.txt'), findsNothing);
      } finally {
        if (!initialBuckets.isCompleted) {
          initialBuckets.complete(const <BucketInfo>[
            BucketInfo(name: '初始迟到桶'),
          ]);
        }
        if (!recoveryBuckets.isCompleted) {
          recoveryBuckets.complete(const <BucketInfo>[
            BucketInfo(name: '桌面文件'),
          ]);
        }
        if (!pendingA.isCompleted) {
          pendingA.complete(
            const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Desktop upload completion does not supersede a pending destination listing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final originalPicker = FilePickerPlatform.instance;
      final pendingUpload = Completer<void>();
      final pendingB = Completer<ObjectListPage>();
      try {
        SharedPreferences.setMockInitialValues({});
        FilePickerPlatform.instance = _FakeFilePicker(<PlatformFile>[
          _TestPlatformFile(
            name: 'uploaded.txt',
            uri: Uri.file('/tmp/uploaded.txt'),
          ),
        ]);
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '桌面文件')],
          objectPagesByPrefix: const <String, ObjectListPage>{
            '': ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(key: 'A/', size: 0, lastModified: '', isDir: true),
              ],
              nextToken: '',
            ),
            'A/': ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(
                  key: 'A/A-source.txt',
                  size: 24,
                  lastModified: '2026-08-31',
                  isDir: false,
                ),
                ObjectInfo(key: 'A/B/', size: 0, lastModified: '', isDir: true),
              ],
              nextToken: '',
            ),
          },
        );
        api.nextUploadFile = pendingUpload;
        api.nextObjectPagesByPrefix['A/B/'] = pendingB;

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('桌面文件'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('A'));
        await tester.pumpAndSettle();
        expect(find.text('A-source.txt'), findsOneWidget);

        // Start an A upload, then dismiss its progress dialog so navigation
        // can move to B while its first page is still on the wire.
        final actionBar = tester.widget<FileManagerActionBar>(
          find.byType(FileManagerActionBar),
        );
        expect(actionBar.onUpload, isNotNull);
        actionBar.onUpload!();
        await tester.pump();
        await tester.pump();
        expect(api.nextUploadFile, isNull);
        expect(find.text('后台运行'), findsOneWidget);
        final backgroundButton = tester.widget<ShadButton>(
          find.ancestor(
            of: find.text('后台运行'),
            matching: find.byType(ShadButton),
          ),
        );
        backgroundButton.onPressed!();
        // The upload remains deliberately pending, so do not settle the fake
        // clock through the progress dialog's active task polling.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final aRequestsBeforeB = api.objectPagePrefixes
            .where((prefix) => prefix == 'A/')
            .length;
        await tester.tap(find.text('B'));
        await tester.pump();
        await tester.pump();
        expect(
          api.objectPagePrefixes.where((prefix) => prefix == 'A/B/').length,
          1,
        );

        // B has begun loading, but active fields still describe A until B's
        // response arrives. A's late completion must not reload A and advance
        // the listing generation over B's pending request.
        pendingUpload.complete();
        await tester.pump();
        await tester.pump();
        expect(
          api.objectPagePrefixes.where((prefix) => prefix == 'A/').length,
          aRequestsBeforeB,
        );

        pendingB.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'A/B/B-destination.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('B-destination.txt'), findsOneWidget);
        expect(find.text('A-source.txt'), findsNothing);
      } finally {
        if (!pendingUpload.isCompleted) pendingUpload.complete();
        if (!pendingB.isCompleted) {
          pendingB.complete(
            const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          );
        }
        FilePickerPlatform.instance = originalPicker;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android uses the touch-first file page without desktop tools', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();

      expect(find.byType(MobileFileManagerPage), findsOneWidget);
      expect(find.byType(MobileFileManagerSurface), findsOneWidget);
      expect(find.byType(FileManagerActionBar), findsNothing);
      expect(find.byType(FileManagerBreadcrumbBar), findsNothing);
      expect(find.text('首页'), findsNothing);
      expect(find.text('设置'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MobileFileManagerSurface),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
      expect(find.text('手机文件'), findsOneWidget);

      final search = find.descendant(
        of: find.byType(MobileFileManagerSurface),
        matching: find.byType(ShadInput),
      );
      expect(tester.getSize(search).height, 48);
      await tester.enterText(search, '没有匹配');
      await tester.pump();
      expect(find.text('没有匹配的存储桶'), findsOneWidget);

      await tester.enterText(search, '');
      await tester.pump();
      final bucketRow = find
          .ancestor(
            of: find.text('手机文件'),
            matching: find.byType(GestureDetector),
          )
          .first;
      await tester.tap(bucketRow);
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      expect(find.text('上传文件'), findsOneWidget);
      expect(find.text('新建文件夹'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(AppShadDialog), findsNothing);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('手机文件'), findsOneWidget);
      final menu = find.descendant(
        of: bucketRow,
        matching: find.byIcon(LucideIcons.ellipsisVertical),
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.byType(AppShadDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android file Back stays ahead of tab history and top Back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/二级/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/二级/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/二级/说明.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      // Build a real tab history; file-location Back must not fall into it.
      await tester.tap(find.text('账号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('二级'));
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MobileNavigationBar<SidebarItem>>(
              find.byType(MobileNavigationBar<SidebarItem>),
            )
            .selectedValue,
        SidebarItem.fileManager,
      );
      expect(find.text('二级'), findsOneWidget);
      expect(find.text('说明.txt'), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();
      expect(find.text('资料'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();
      expect(find.text('所有存储桶'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MobileNavigationBar<SidebarItem>>(
              find.byType(MobileNavigationBar<SidebarItem>),
            )
            .selectedValue,
        SidebarItem.storage,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android soft refresh preserves file Back history', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        freshBootstrapInstances: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/二级/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/二级/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/二级/说明.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('账号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('二级'));
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);

      tester.widget<MainLayoutPage>(find.byType(MainLayoutPage)).onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MobileNavigationBar<SidebarItem>>(
              find.byType(MobileNavigationBar<SidebarItem>),
            )
            .selectedValue,
        SidebarItem.fileManager,
      );
      expect(find.text('二级'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();
      expect(find.text('资料'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android refresh rebinds Back history to a changed profile', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      RemoteStorageConfig profileConfig(String rootPrefix) =>
          RemoteStorageConfig.empty().copyWith(
            endpoint: 'https://s3.example.com',
            displayName: '测试账号',
            profileId: 'profile-id',
            rootPrefix: rootPrefix,
          );

      final profileConfigs = <String, RemoteStorageConfig>{
        'profile': profileConfig('old-root'),
      };
      final api = _FakeApi(
        configured: true,
        configOverride: profileConfigs['profile'],
        freshBootstrapInstances: true,
        profiles: const <ProfileInfo>[
          ProfileInfo(
            name: 'profile',
            displayName: '测试账号',
            storageType: StorageType.s3,
            providerType: StorageProviderType.s3,
            endpoint: 'https://s3.example.com',
            accessKeyId: 'AKIA_TEST',
          ),
        ],
        profileConfigs: profileConfigs,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/说明.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);

      profileConfigs['profile'] = profileConfig('new-root');
      tester.widget<MainLayoutPage>(find.byType(MainLayoutPage)).onRefresh();
      await tester.pumpAndSettle();

      expect(find.text('说明.txt'), findsOneWidget);
      expect(api.objectPageConfigs.last.rootPrefix, 'new-root');
      expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
      final requestsBeforeBack = api.objectPageConfigs.length;
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('资料'), findsOneWidget);
      // The previous root page was cached with old-root. Back must fetch it
      // through the fresh rebound entry instead of silently reusing that page.
      expect(api.objectPageConfigs.length, greaterThan(requestsBeforeBack));
      expect(api.objectPageConfigs.last.rootPrefix, 'new-root');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Android create confirmation is canceled when profile refresh starts',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues({});
        RemoteStorageConfig profileConfig(String rootPrefix) =>
            RemoteStorageConfig.empty().copyWith(
              endpoint: 'https://s3.example.com',
              displayName: '测试账号',
              profileId: 'profile-id',
              rootPrefix: rootPrefix,
            );
        final profileConfigs = <String, RemoteStorageConfig>{
          'profile': profileConfig('old-root'),
        };
        final api = _FakeApi(
          configured: true,
          configOverride: profileConfigs['profile'],
          freshBootstrapInstances: true,
          profiles: const <ProfileInfo>[
            ProfileInfo(
              name: 'profile',
              displayName: '测试账号',
              storageType: StorageType.s3,
              providerType: StorageProviderType.s3,
              endpoint: 'https://s3.example.com',
              accessKeyId: 'AKIA_TEST',
            ),
          ],
          profileConfigs: profileConfigs,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: const <String, ObjectListPage>{
            '': ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(
                  key: '说明.txt',
                  size: 1,
                  lastModified: '',
                  isDir: false,
                ),
              ],
              nextToken: '',
            ),
          },
        );

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手机文件'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(LucideIcons.plus));
        await tester.pumpAndSettle();
        await tester.tap(find.text('新建文件夹'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(ShadInput).last, '不会创建');

        // Keep the confirmation sheet open while the bootstrap/profile input
        // changes. The old dialog must not write through old-root.
        profileConfigs['profile'] = profileConfig('new-root');
        tester.widget<MainLayoutPage>(find.byType(MainLayoutPage)).onRefresh();
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ShadButton, '创建'));
        await tester.pumpAndSettle();

        expect(api.createDirectoryConfigs, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android picker result is discarded when profile refresh starts',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final originalPicker = FilePickerPlatform.instance;
      final picked = Completer<List<PlatformFile>>();
      try {
        SharedPreferences.setMockInitialValues({});
        RemoteStorageConfig profileConfig(String rootPrefix) =>
            RemoteStorageConfig.empty().copyWith(
              endpoint: 'https://s3.example.com',
              displayName: '测试账号',
              profileId: 'profile-id',
              rootPrefix: rootPrefix,
            );
        final profileConfigs = <String, RemoteStorageConfig>{
          'profile': profileConfig('old-root'),
        };
        final api = _FakeApi(
          configured: true,
          configOverride: profileConfigs['profile'],
          freshBootstrapInstances: true,
          profiles: const <ProfileInfo>[
            ProfileInfo(
              name: 'profile',
              displayName: '测试账号',
              storageType: StorageType.s3,
              providerType: StorageProviderType.s3,
              endpoint: 'https://s3.example.com',
              accessKeyId: 'AKIA_TEST',
            ),
          ],
          profileConfigs: profileConfigs,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: const <String, ObjectListPage>{
            '': ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          },
        );
        FilePickerPlatform.instance = _PendingFilePicker(picked.future);

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手机文件'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(LucideIcons.plus));
        await tester.pumpAndSettle();
        await tester.tap(find.text('上传文件'));
        await tester.pump();
        await tester.pump();

        // The native picker is still pending; rebind the profile before it
        // returns, then prove no upload reaches the old entry/config.
        profileConfigs['profile'] = profileConfig('new-root');
        tester.widget<MainLayoutPage>(find.byType(MainLayoutPage)).onRefresh();
        await tester.pumpAndSettle();
        picked.complete(<PlatformFile>[
          _TestPlatformFile(name: '迟到上传.txt', uri: Uri.file('/tmp/迟到上传.txt')),
        ]);
        await tester.pumpAndSettle();

        expect(api.uploadFileConfigs, isEmpty);
      } finally {
        FilePickerPlatform.instance = originalPicker;
        if (!picked.isCompleted) picked.complete(const <PlatformFile>[]);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android download picker result is discarded when profile refresh starts',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final originalPicker = FilePickerPlatform.instance;
      final selectedDirectory = Completer<String?>();
      try {
        SharedPreferences.setMockInitialValues({});
        RemoteStorageConfig profileConfig(String rootPrefix) =>
            RemoteStorageConfig.empty().copyWith(
              endpoint: 'https://s3.example.com',
              displayName: '测试账号',
              profileId: 'profile-id',
              rootPrefix: rootPrefix,
              defaultDownloadDirectory: '/tmp',
            );
        final profileConfigs = <String, RemoteStorageConfig>{
          'profile': profileConfig('old-root'),
        };
        final api = _FakeApi(
          configured: true,
          configOverride: profileConfigs['profile'],
          freshBootstrapInstances: true,
          profiles: const <ProfileInfo>[
            ProfileInfo(
              name: 'profile',
              displayName: '测试账号',
              storageType: StorageType.s3,
              providerType: StorageProviderType.s3,
              endpoint: 'https://s3.example.com',
              accessKeyId: 'AKIA_TEST',
            ),
          ],
          profileConfigs: profileConfigs,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: const <String, ObjectListPage>{
            '': ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(
                  key: '待下载目录/',
                  size: 0,
                  lastModified: '',
                  isDir: true,
                ),
              ],
              nextToken: '',
            ),
          },
        );
        FilePickerPlatform.instance = _PendingDirectoryPicker(
          selectedDirectory.future,
        );

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手机文件'));
        await tester.pumpAndSettle();
        final objectRow = find.byKey(
          const ValueKey<String>('mobile-object-待下载目录/'),
        );
        await tester.tap(
          find.descendant(
            of: objectRow,
            matching: find.byIcon(LucideIcons.ellipsisVertical),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('下载'));
        await tester.pump();
        await tester.pump();

        // Directory selection remains open while the profile source rebinds.
        // Completing it afterwards must not start a listing through old-root.
        profileConfigs['profile'] = profileConfig('new-root');
        tester.widget<MainLayoutPage>(find.byType(MainLayoutPage)).onRefresh();
        await tester.pump();
        await tester.pump();
        await tester.pump();
        final requestsAfterRebind = api.objectPageConfigs.length;
        selectedDirectory.complete('/tmp');
        // The progress sheet intentionally stays open after a terminal task;
        // pump its completion, then close it as a user would.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(api.objectPageConfigs.length, requestsAfterRebind);
        expect(api.downloadFileConfigs, isEmpty);
        expect(
          TransferQueue.instance.tasks.single.status,
          TransferStatus.canceled,
        );
        await tester.tap(find.widgetWithText(ShadButton, '关闭'));
        await tester.pumpAndSettle();
      } finally {
        FilePickerPlatform.instance = originalPicker;
        if (!selectedDirectory.isCompleted) selectedDirectory.complete(null);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android Back returns from an in-flight bucket before tabs', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('账号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();

      final pendingObjects = Completer<ObjectListPage>();
      api.nextObjectPage = pendingObjects;
      await tester.tap(find.text('手机文件'));
      await tester.pump();
      expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MobileNavigationBar<SidebarItem>>(
              find.byType(MobileNavigationBar<SidebarItem>),
            )
            .selectedValue,
        SidebarItem.fileManager,
      );
      expect(find.text('所有存储桶'), findsOneWidget);

      pendingObjects.complete(
        const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
      );
      await tester.pumpAndSettle();
      expect(find.text('所有存储桶'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Android top Back returns from loading bucket and directory before tabs',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues({});
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: const <String, ObjectListPage>{
            '': ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(
                  key: '根目录.txt',
                  size: 24,
                  lastModified: '2026-08-31',
                  isDir: false,
                ),
                ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
              ],
              nextToken: '',
            ),
          },
        );

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        // A prior tab visit makes a wrong fallback observable immediately.
        await tester.tap(find.text('账号'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('文件'));
        await tester.pumpAndSettle();

        final pendingBucket = Completer<ObjectListPage>();
        api.nextObjectPagesByPrefix[''] = pendingBucket;
        await tester.tap(find.text('手机文件'));
        await tester.pump();
        expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);

        await tester.tap(find.byIcon(LucideIcons.chevronLeft));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MobileNavigationBar<SidebarItem>>(
                find.byType(MobileNavigationBar<SidebarItem>),
              )
              .selectedValue,
          SidebarItem.fileManager,
        );
        expect(find.text('所有存储桶'), findsOneWidget);

        pendingBucket.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '迟到桶响应.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('所有存储桶'), findsOneWidget);
        expect(find.text('迟到桶响应.txt'), findsNothing);

        await tester.tap(find.text('手机文件'));
        await tester.pumpAndSettle();
        expect(find.text('根目录.txt'), findsOneWidget);

        final pendingDirectory = Completer<ObjectListPage>();
        api.nextObjectPagesByPrefix['资料/'] = pendingDirectory;
        await tester.tap(find.text('资料'));
        await tester.pump();
        expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);

        await tester.tap(find.byIcon(LucideIcons.chevronLeft));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MobileNavigationBar<SidebarItem>>(
                find.byType(MobileNavigationBar<SidebarItem>),
              )
              .selectedValue,
          SidebarItem.fileManager,
        );
        expect(find.text('根目录.txt'), findsOneWidget);

        pendingDirectory.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/迟到目录响应.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('根目录.txt'), findsOneWidget);
        expect(find.text('迟到目录响应.txt'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android ignores a late object page after Back', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: <String, ObjectListPage>{
          '': const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '根目录.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: List<ObjectInfo>.generate(
              12,
              (index) => ObjectInfo(
                key: '资料/第$index页.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ),
            nextToken: '资料-p2',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();

      final pendingPage = Completer<ObjectListPage>();
      api.nextObjectPage = pendingPage;
      final list = find.descendant(
        of: find.byType(MobileFileManagerBrowser),
        matching: find.byType(Scrollable),
      );
      await tester.drag(list.first, const Offset(0, -10000));
      await tester.pump();
      expect(api.nextObjectPage, isNull);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('根目录.txt'), findsOneWidget);

      pendingPage.complete(
        const ObjectListPage(
          items: <ObjectInfo>[
            ObjectInfo(
              key: '资料/迟到页.txt',
              size: 24,
              lastModified: '2026-08-31',
              isDir: false,
            ),
          ],
          nextToken: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('根目录.txt'), findsOneWidget);
      expect(find.text('迟到页.txt'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android ignores a late trash page after Back', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/说明.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
        trashPagesByToken: <String, TrashListPage>{
          '': TrashListPage(
            items: List<TrashItem>.generate(
              12,
              (index) => TrashItem(
                id: 'trash-$index',
                name: '已删$index.txt',
                originalKey: '资料/已删$index.txt',
                trashKey: '.trash/$index',
                deletedAt: '2026-08-31',
                isDir: false,
                size: 24,
                objectCount: 0,
              ),
            ),
            nextToken: 'trash-p2',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开回收站'));
      await tester.pumpAndSettle();
      expect(find.text('已删0.txt'), findsOneWidget);

      final pendingPage = Completer<TrashListPage>();
      api.nextTrashPage = pendingPage;
      final list = find.descendant(
        of: find.byType(MobileFileManagerBrowser),
        matching: find.byType(Scrollable),
      );
      await tester.drag(list.first, const Offset(0, -1000));
      await tester.pump();
      expect(api.nextTrashPage, isNull);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开回收站'));
      await tester.pumpAndSettle();
      expect(find.text('已删0.txt'), findsOneWidget);

      pendingPage.complete(
        const TrashListPage(
          items: <TrashItem>[
            TrashItem(
              id: 'late-trash',
              name: '迟到回收站项.txt',
              originalKey: '资料/迟到回收站项.txt',
              trashKey: '.trash/late',
              deletedAt: '2026-08-31',
              isDir: false,
              size: 24,
              objectCount: 0,
            ),
          ],
          nextToken: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已删0.txt'), findsOneWidget);
      expect(find.text('迟到回收站项.txt'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android does not reopen trash after a late restore', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/说明.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
        trashPagesByToken: const <String, TrashListPage>{
          '': TrashListPage(
            items: <TrashItem>[
              TrashItem(
                id: 'restore-late',
                name: '已删文件.txt',
                originalKey: '资料/已删文件.txt',
                trashKey: '.trash/restore-late',
                deletedAt: '2026-08-31',
                isDir: false,
                size: 24,
                objectCount: 0,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开回收站'));
      await tester.pumpAndSettle();

      final pendingRestore = Completer<void>();
      api.nextRestoreTrashItem = pendingRestore;
      await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(api.nextRestoreTrashItem, isNull);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);

      pendingRestore.complete();
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);
      expect(find.text('回收站 · 手机文件'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android ignores a late mutation reload after Back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '根目录.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/原文件.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建文件夹'));
      await tester.pumpAndSettle();

      final pendingCreate = Completer<void>();
      final pendingReload = Completer<ObjectListPage>();
      api.nextCreateDirectory = pendingCreate;
      api.nextObjectPage = pendingReload;
      await tester.enterText(find.byType(ShadInput).last, '新目录');
      await tester.tap(find.widgetWithText(ShadButton, '创建'));
      await tester.pump();
      expect(api.nextCreateDirectory, isNull);

      pendingCreate.complete();
      await tester.pump();
      await tester.pump();
      expect(api.nextObjectPage, isNull);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('根目录.txt'), findsOneWidget);

      pendingReload.complete(
        const ObjectListPage(
          items: <ObjectInfo>[
            ObjectInfo(key: '资料/新目录/', size: 0, lastModified: '', isDir: true),
          ],
          nextToken: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('根目录.txt'), findsOneWidget);
      expect(find.text('新目录'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android Back restores the directory that opened bucket trash', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/说明.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开回收站'));
      await tester.pumpAndSettle();
      expect(find.text('回收站 · 手机文件'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android folder overflow opens the selected directory', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/说明.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开文件夹'));
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android sync remote open enters a file location with Back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          '资料/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/同步说明.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('账号'));
      await tester.pumpAndSettle();

      SyncDirectoryNavigation.instance.openRemote(
        const SyncRemoteOpenRequest(
          profileName: '',
          bucket: '手机文件',
          remotePrefix: '资料',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('同步说明.txt'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('所有存储桶'), findsOneWidget);
      expect(
        tester
            .widget<MobileNavigationBar<SidebarItem>>(
              find.byType(MobileNavigationBar<SidebarItem>),
            )
            .selectedValue,
        SidebarItem.fileManager,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Android sync remote open keeps the latest target when an older one finishes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues({});
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: const <String, ObjectListPage>{
            '': ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          },
        );
        final pendingA = Completer<ObjectListPage>();
        final pendingB = Completer<ObjectListPage>();
        api.nextObjectPagesByPrefix['A/'] = pendingA;
        api.nextObjectPagesByPrefix['B/'] = pendingB;

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();

        SyncDirectoryNavigation.instance.openRemote(
          const SyncRemoteOpenRequest(
            profileName: '',
            bucket: '手机文件',
            remotePrefix: 'A',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(api.objectPagePrefixes, contains('A/'));

        SyncDirectoryNavigation.instance.openRemote(
          const SyncRemoteOpenRequest(
            profileName: '',
            bucket: '手机文件',
            remotePrefix: 'B',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(api.objectPagePrefixes, contains('B/'));

        pendingA.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'A/A-stale.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('A-stale.txt'), findsNothing);
        expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);

        pendingB.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'B/B-latest.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('B-latest.txt'), findsOneWidget);
        expect(find.text('A-stale.txt'), findsNothing);

        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('所有存储桶'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android missing sync replacement restores the origin without a spinner',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pendingA = Completer<ObjectListPage>();
      try {
        SharedPreferences.setMockInitialValues({});
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        );
        api.nextObjectPagesByPrefix['A/'] = pendingA;

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();

        SyncDirectoryNavigation.instance.openRemote(
          const SyncRemoteOpenRequest(
            profileName: '',
            bucket: '手机文件',
            remotePrefix: 'A',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(api.objectPagePrefixes, contains('A/'));
        expect(find.text('加载中...'), findsOneWidget);

        // B replaces A before A responds, but no such bucket exists. The
        // file page must reload the saved origin instead of retaining A's
        // loading surface or falling through to a bottom-bar page.
        SyncDirectoryNavigation.instance.openRemote(
          const SyncRemoteOpenRequest(
            profileName: '',
            bucket: '不存在的手机文件',
            remotePrefix: 'B',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('所有存储桶'), findsOneWidget);
        expect(find.text('加载中...'), findsNothing);
        expect(find.byIcon(LucideIcons.chevronLeft), findsNothing);

        pendingA.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'A/迟到响应.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('所有存储桶'), findsOneWidget);
        expect(find.text('迟到响应.txt'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        if (!pendingA.isCompleted) {
          pendingA.complete(
            const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          );
        }
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android Back cancels a slow sync bucket discovery', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final pendingBuckets = Completer<List<BucketInfo>>();
      final api = _FakeApi(configured: true);
      api.bucketListingFuture = pendingBuckets.future;

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(MobileNavigationBar<SidebarItem>), findsOneWidget);

      SyncDirectoryNavigation.instance.openRemote(
        const SyncRemoteOpenRequest(
          profileName: '',
          bucket: '手机文件',
          remotePrefix: '资料',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
      expect(api.objectPagePrefixes, isEmpty);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(
        tester
            .widget<MobileNavigationBar<SidebarItem>>(
              find.byType(MobileNavigationBar<SidebarItem>),
            )
            .selectedValue,
        SidebarItem.fileManager,
      );
      expect(find.byIcon(LucideIcons.chevronLeft), findsNothing);

      pendingBuckets.complete(const <BucketInfo>[BucketInfo(name: '手机文件')]);
      await tester.pumpAndSettle();
      expect(find.text('所有存储桶'), findsOneWidget);
      expect(api.objectPagePrefixes, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android sync cancel preserves nested file Back history', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(key: 'A/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          'A/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'A/A-file.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
              ObjectInfo(key: 'A/B/', size: 0, lastModified: '', isDir: true),
            ],
            nextToken: '',
          ),
          'A/B/': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: 'A/B/B-file.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(find.text('B-file.txt'), findsOneWidget);

      // The first successful sync leaves a prior A location in history.
      SyncDirectoryNavigation.instance.openRemote(
        const SyncRemoteOpenRequest(
          profileName: '',
          bucket: '手机文件',
          remotePrefix: 'A',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A-file.txt'), findsOneWidget);

      final pendingD = Completer<ObjectListPage>();
      api.nextObjectPagesByPrefix['A/D/'] = pendingD;
      SyncDirectoryNavigation.instance.openRemote(
        const SyncRemoteOpenRequest(
          profileName: '',
          bucket: '手机文件',
          remotePrefix: 'A/D',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(api.objectPagePrefixes, contains('A/D/'));

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      pendingD.complete(
        const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
      );
      await tester.pumpAndSettle();
      expect(find.text('A-file.txt'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('B-file.txt'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('A-file.txt'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Android upload completion refreshes its source without reloading another directory',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final originalPicker = FilePickerPlatform.instance;
      final pendingUpload = Completer<void>();
      try {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        SharedPreferences.setMockInitialValues({});
        FilePickerPlatform.instance = _FakeFilePicker(<PlatformFile>[
          _TestPlatformFile(
            name: 'uploaded.txt',
            uri: Uri.file('/tmp/uploaded.txt'),
          ),
        ]);
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: <String, ObjectListPage>{
            '': const ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(key: 'A/', size: 0, lastModified: '', isDir: true),
                ObjectInfo(key: 'B/', size: 0, lastModified: '', isDir: true),
              ],
              nextToken: '',
            ),
            'A/': const ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(
                  key: 'A/A-old.txt',
                  size: 24,
                  lastModified: '2026-08-31',
                  isDir: false,
                ),
              ],
              nextToken: '',
            ),
            'B/': const ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(
                  key: 'B/B-stable.txt',
                  size: 24,
                  lastModified: '2026-08-31',
                  isDir: false,
                ),
              ],
              nextToken: '',
            ),
          },
        );
        api.nextUploadFile = pendingUpload;

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手机文件'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('A'));
        await tester.pumpAndSettle();
        expect(find.text('A-old.txt'), findsOneWidget);

        await tester.tap(find.byIcon(LucideIcons.plus));
        await tester.pumpAndSettle();
        await tester.tap(find.text('上传文件'));
        await tester.pump();
        await tester.pump();
        expect(api.nextUploadFile, isNull);
        expect(find.text('后台运行'), findsOneWidget);
        final backgroundButton = tester.widget<ShadButton>(
          find.ancestor(
            of: find.text('后台运行'),
            matching: find.byType(ShadButton),
          ),
        );
        backgroundButton.onPressed!();
        await tester.pumpAndSettle();

        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        await tester.tap(find.text('B'));
        await tester.pumpAndSettle();
        expect(find.text('B-stable.txt'), findsOneWidget);
        final bRequestsBeforeCompletion = api.objectPagePrefixes
            .where((prefix) => prefix == 'B/')
            .length;

        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        await tester.tap(find.text('A'));
        await tester.pumpAndSettle();
        // A still renders its pre-upload cache after the user returns early.
        expect(find.text('A-old.txt'), findsOneWidget);

        api.objectPagesByPrefix['A/'] = const ObjectListPage(
          items: <ObjectInfo>[
            ObjectInfo(
              key: 'A/A-new.txt',
              size: 24,
              lastModified: '2026-08-31',
              isDir: false,
            ),
          ],
          nextToken: '',
        );
        pendingUpload.complete();
        await tester.pumpAndSettle();
        expect(
          api.objectPagePrefixes.where((prefix) => prefix == 'B/').length,
          bRequestsBeforeCompletion,
        );
        expect(find.text('A-new.txt'), findsOneWidget);
        expect(find.text('A-old.txt'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        if (!pendingUpload.isCompleted) {
          pendingUpload.complete();
        }
        FilePickerPlatform.instance = originalPicker;
        await tester.binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android delete completion keeps an opened bucket trash visible',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pendingDelete = Completer<void>();
      try {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        SharedPreferences.setMockInitialValues({});
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: const <String, ObjectListPage>{
            '': ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(
                  key: '待删除.txt',
                  size: 24,
                  lastModified: '2026-08-31',
                  isDir: false,
                ),
              ],
              nextToken: '',
            ),
          },
        );
        api.nextDeleteObject = pendingDelete;

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手机文件'));
        await tester.pumpAndSettle();

        final objectRow = find.byKey(const ValueKey('mobile-object-待删除.txt'));
        await tester.tap(
          find.descendant(
            of: objectRow,
            matching: find.byIcon(LucideIcons.ellipsisVertical),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ShadButton, '删除'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ShadButton, '删除'));
        await tester.pump();
        await tester.pump();
        expect(api.nextDeleteObject, isNull);
        expect(find.text('后台运行'), findsOneWidget);

        final backgroundButton = tester.widget<ShadButton>(
          find.ancestor(
            of: find.text('后台运行'),
            matching: find.byType(ShadButton),
          ),
        );
        backgroundButton.onPressed!();
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(LucideIcons.ellipsis));
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开回收站'));
        await tester.pumpAndSettle();
        expect(find.text('回收站 · 手机文件'), findsOneWidget);

        pendingDelete.complete();
        await tester.pumpAndSettle();
        expect(find.text('回收站 · 手机文件'), findsOneWidget);
        expect(find.text('待删除.txt'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        if (!pendingDelete.isCompleted) pendingDelete.complete();
        await tester.binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android restored-listing refresh supersedes late object pages and cache',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues({});
        final initialItems = List<ObjectInfo>.generate(
          12,
          (index) => ObjectInfo(
            key: '资料/原页$index.txt',
            size: 24,
            lastModified: '2026-08-31',
            isDir: false,
          ),
        );
        final refreshedItems = List<ObjectInfo>.generate(
          12,
          (index) => ObjectInfo(
            key: '资料/刷新后$index.txt',
            size: 24,
            lastModified: '2026-08-31',
            isDir: false,
          ),
        );
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: <String, ObjectListPage>{
            '': const ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
              ],
              nextToken: '',
            ),
            '资料/': ObjectListPage(items: initialItems, nextToken: 'p2'),
          },
        );

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手机文件'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('资料'));
        await tester.pumpAndSettle();

        final pendingPage = Completer<ObjectListPage>();
        api.nextObjectPage = pendingPage;
        final list = find.descendant(
          of: find.byType(MobileFileManagerBrowser),
          matching: find.byType(Scrollable),
        );
        await tester.drag(list.first, const Offset(0, -1000));
        await tester.pump();
        expect(api.nextObjectPage, isNull);

        final refreshedPage = Completer<ObjectListPage>();
        api.nextObjectPage = refreshedPage;
        ObjectListingNotifier.instance.markRestored('手机文件', const [
          TrashItem(
            id: 'restored-item',
            name: '已恢复.txt',
            originalKey: '资料/已恢复.txt',
            trashKey: '.trash/restored-item',
            deletedAt: '2026-08-31',
            isDir: false,
            size: 24,
            objectCount: 0,
          ),
        ]);
        await tester.pump();
        expect(api.nextObjectPage, isNull);

        refreshedPage.complete(
          ObjectListPage(items: refreshedItems, nextToken: 'p2'),
        );
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 1000));
        await tester.pump();
        expect(find.text('刷新后0.txt'), findsOneWidget);

        pendingPage.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/过期分页.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('过期分页.txt'), findsNothing);

        final freshPage = Completer<ObjectListPage>();
        api.nextObjectPage = freshPage;
        await tester.drag(list.first, const Offset(0, -1000));
        await tester.pump();
        expect(api.nextObjectPage, isNull);
        freshPage.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/新分页.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('新分页.txt'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android failed restore refresh releases the superseded object pager',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final stalePageTwo = Completer<ObjectListPage>();
      final failedRefresh = Completer<ObjectListPage>();
      final freshPageTwo = Completer<ObjectListPage>();
      try {
        SharedPreferences.setMockInitialValues({});
        final initialItems = List<ObjectInfo>.generate(
          12,
          (index) => ObjectInfo(
            key: '资料/初始$index.txt',
            size: 24,
            lastModified: '2026-08-31',
            isDir: false,
          ),
        );
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: <String, ObjectListPage>{
            '': const ObjectListPage(
              items: <ObjectInfo>[
                ObjectInfo(key: '资料/', size: 0, lastModified: '', isDir: true),
              ],
              nextToken: '',
            ),
            '资料/': ObjectListPage(items: initialItems, nextToken: 'p2'),
          },
        );

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手机文件'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('资料'));
        await tester.pumpAndSettle();

        final list = find.descendant(
          of: find.byType(MobileFileManagerBrowser),
          matching: find.byType(Scrollable),
        );
        api.nextObjectPage = stalePageTwo;
        await tester.drag(list.first, const Offset(0, -1000));
        await tester.pump();
        expect(api.nextObjectPage, isNull);

        // The restore refresh invalidates the old paging request. Let its
        // first page fail while page two is still pending.
        api.nextObjectPage = failedRefresh;
        ObjectListingNotifier.instance.markRestored('手机文件', const [
          TrashItem(
            id: 'restored-failure',
            name: '已恢复.txt',
            originalKey: '资料/已恢复.txt',
            trashKey: '.trash/restored-failure',
            deletedAt: '2026-08-31',
            isDir: false,
            size: 24,
            objectCount: 0,
          ),
        ]);
        await tester.pump();
        expect(api.nextObjectPage, isNull);
        failedRefresh.completeError(StateError('静默刷新失败'));
        await tester.pump();
        await tester.pump();

        // A fresh bottom reach must start another page even though the stale
        // request has not returned to run its now-invalid finally block.
        api.nextObjectPage = freshPageTwo;
        await tester.drag(list.first, const Offset(0, 1000));
        await tester.pump();
        await tester.drag(list.first, const Offset(0, -1000));
        await tester.pump();
        expect(api.nextObjectPage, isNull);

        stalePageTwo.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/过期分页.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pump();
        expect(find.text('过期分页.txt'), findsNothing);

        freshPageTwo.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '资料/可继续分页.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('可继续分页.txt'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        if (!stalePageTwo.isCompleted) {
          stalePageTwo.complete(
            const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          );
        }
        if (!failedRefresh.isCompleted) {
          failedRefresh.complete(
            const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          );
        }
        if (!freshPageTwo.isCompleted) {
          freshPageTwo.complete(
            const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          );
        }
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android failed rename invalidates an in-flight object page and cache',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final stalePageTwo = Completer<ObjectListPage>();
      final failedRename = Completer<void>();
      final refreshedPage = Completer<ObjectListPage>();
      final freshPageTwo = Completer<ObjectListPage>();
      try {
        SharedPreferences.setMockInitialValues({});
        final initialItems = List<ObjectInfo>.generate(
          12,
          (index) => ObjectInfo(
            key: '初始$index.txt',
            size: 24,
            lastModified: '2026-08-31',
            isDir: false,
          ),
        );
        final api = _FakeApi(
          configured: true,
          buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
          objectPagesByPrefix: <String, ObjectListPage>{
            '': ObjectListPage(items: initialItems, nextToken: 'p2'),
          },
        );

        await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手机文件'));
        await tester.pumpAndSettle();

        final list = find.descendant(
          of: find.byType(MobileFileManagerBrowser),
          matching: find.byType(Scrollable),
        );
        api.nextObjectPage = stalePageTwo;
        await tester.drag(list.first, const Offset(0, -1000));
        await tester.pump();
        expect(api.nextObjectPage, isNull);

        final objectRow = find.byKey(const ValueKey('mobile-object-初始11.txt'));
        await tester.ensureVisible(objectRow);
        final objectMenu = find.descendant(
          of: objectRow,
          matching: find.byIcon(LucideIcons.ellipsisVertical),
        );
        await tester.tap(objectMenu);
        // Page two deliberately remains pending, so do not settle its spinner.
        await tester.pump(const Duration(milliseconds: 320));
        final renameButton = tester.widget<ShadButton>(
          find.ancestor(
            of: find.text('重命名'),
            matching: find.byType(ShadButton),
          ),
        );
        renameButton.onPressed!();
        await tester.pump(const Duration(milliseconds: 320));
        await tester.enterText(find.byType(ShadInput).last, '失败后重命名.txt');
        api.nextRenameObject = failedRename;
        final saveButton = tester.widget<ShadButton>(
          find.ancestor(of: find.text('保存'), matching: find.byType(ShadButton)),
        );
        saveButton.onPressed!();
        await tester.pump();
        expect(api.nextRenameObject, isNull);

        // A provider failure can happen after a partial mutation. Its refresh
        // must supersede the page-two request before that stale page can cache.
        api.nextObjectPage = refreshedPage;
        failedRename.completeError(StateError('重命名失败'));
        await tester.pump();
        expect(api.nextObjectPage, isNull);
        refreshedPage.complete(
          ObjectListPage(items: initialItems, nextToken: 'p2'),
        );
        await tester.pumpAndSettle();
        expect(find.text('操作失败'), findsOneWidget);
        await tester.tap(find.widgetWithText(ShadButton, '知道了'));
        await tester.pumpAndSettle();

        stalePageTwo.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '过期分页.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pump();
        expect(find.text('过期分页.txt'), findsNothing);

        // It must also release the stale pager; a later reach obtains a fresh
        // page rather than reusing the old response from the invalidated cache.
        api.nextObjectPage = freshPageTwo;
        await tester.drag(list.first, const Offset(0, 1000));
        await tester.pump();
        await tester.drag(list.first, const Offset(0, -1000));
        await tester.pump();
        expect(api.nextObjectPage, isNull);
        freshPageTwo.complete(
          const ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '新分页.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('新分页.txt'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        TransferQueue.instance.resetForTest();
        RemoteTaskStore.instance.resetForTest();
        SyncProfileNotifier.instance.stop();
      } finally {
        if (!stalePageTwo.isCompleted) {
          stalePageTwo.complete(
            const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          );
        }
        if (!failedRename.isCompleted) {
          failedRename.complete();
        }
        if (!refreshedPage.isCompleted) {
          refreshedPage.complete(
            const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          );
        }
        if (!freshPageTwo.isCompleted) {
          freshPageTwo.complete(
            const ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
          );
        }
        await tester.binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android trash mutation reload supersedes a late trash page', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    try {
      SharedPreferences.setMockInitialValues({});
      final initialItems = List<TrashItem>.generate(
        18,
        (index) => TrashItem(
          id: 'trash-$index',
          name: '待恢复$index.txt',
          originalKey: '待恢复$index.txt',
          trashKey: '.trash/$index',
          deletedAt: '2026-08-31',
          isDir: false,
          size: 24,
          objectCount: 0,
        ),
      );
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(items: <ObjectInfo>[], nextToken: ''),
        },
        trashPagesByToken: <String, TrashListPage>{
          '': TrashListPage(items: initialItems, nextToken: 'trash-p2'),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开回收站'));
      await tester.pumpAndSettle();

      final pendingPage = Completer<TrashListPage>();
      api.nextTrashPage = pendingPage;
      final list = find.descendant(
        of: find.byType(MobileFileManagerBrowser),
        matching: find.byType(Scrollable),
      );
      await tester.drag(list.first, const Offset(0, -1000));
      await tester.pump();
      expect(api.nextTrashPage, isNull);
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      await tester.pump();

      final refreshedPage = Completer<TrashListPage>();
      api.nextTrashPage = refreshedPage;
      await tester.tap(find.byIcon(LucideIcons.ellipsisVertical).first);
      await tester.pump(const Duration(milliseconds: 300));
      final restoreButton = tester.widget<ShadButton>(
        find.ancestor(of: find.text('恢复'), matching: find.byType(ShadButton)),
      );
      restoreButton.onPressed!();
      await tester.pump();
      expect(api.nextTrashPage, isNull);

      refreshedPage.complete(
        const TrashListPage(
          items: <TrashItem>[
            TrashItem(
              id: 'fresh-trash',
              name: '刷新后回收站项.txt',
              originalKey: '刷新后回收站项.txt',
              trashKey: '.trash/fresh',
              deletedAt: '2026-08-31',
              isDir: false,
              size: 24,
              objectCount: 0,
            ),
          ],
          nextToken: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('刷新后回收站项.txt'), findsOneWidget);

      pendingPage.complete(
        const TrashListPage(
          items: <TrashItem>[
            TrashItem(
              id: 'late-trash',
              name: '过期回收站项.txt',
              originalKey: '过期回收站项.txt',
              trashKey: '.trash/late',
              deletedAt: '2026-08-31',
              isDir: false,
              size: 24,
              objectCount: 0,
            ),
          ],
          nextToken: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('刷新后回收站项.txt'), findsOneWidget);
      expect(find.text('过期回收站项.txt'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android Back closes trash, returns to files, then exits', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var systemPopCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') systemPopCalls++;
        return null;
      },
    );
    try {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        configured: true,
        buckets: const <BucketInfo>[BucketInfo(name: '手机文件')],
        objectPagesByPrefix: const <String, ObjectListPage>{
          '': ObjectListPage(
            items: <ObjectInfo>[
              ObjectInfo(
                key: '说明.txt',
                size: 24,
                lastModified: '2026-08-31',
                isDir: false,
              ),
            ],
            nextToken: '',
          ),
        },
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开回收站'));
      await tester.pumpAndSettle();
      expect(find.text('回收站 · 手机文件'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('说明.txt'), findsOneWidget);
      expect(find.text('回收站 · 手机文件'), findsNothing);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('所有存储桶'), findsOneWidget);

      await tester.tap(find.text('账号'));
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('所有存储桶'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(systemPopCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('object load recovery edits the clicked bucket account', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final s3Config = RemoteStorageConfig.empty().copyWith(
        endpoint: 'https://s3.example.com',
        displayName: 'S3 Account',
        mappedBucketName: 'S3 Account',
        accessKeyId: 's3-access',
        secretAccessKey: 's3-secret',
        hasSecretAccessKey: true,
      );
      final baiduConfig = RemoteStorageConfig.empty().copyWith(
        endpoint: 'https://pan.baidu.com',
        storageType: StorageType.baiduPan,
        providerType: StorageProviderType.baiduPan,
        displayName: '百度账号',
        mappedBucketName: '百度网盘',
        accessKeyId: 'baidu-access',
        secretAccessKey: 'baidu-refresh',
        hasSecretAccessKey: true,
      );
      final api = _FakeApi(
        configured: true,
        configOverride: s3Config,
        profiles: const <ProfileInfo>[
          ProfileInfo(
            name: 's3-profile',
            displayName: 'S3 Account',
            storageType: StorageType.s3,
            providerType: StorageProviderType.s3,
            endpoint: 'https://s3.example.com',
            accessKeyId: 's3-access',
            active: true,
          ),
          ProfileInfo(
            name: 'baidu-profile',
            displayName: '百度账号',
            storageType: StorageType.baiduPan,
            providerType: StorageProviderType.baiduPan,
            endpoint: 'https://pan.baidu.com',
            accessKeyId: 'baidu-access',
          ),
        ],
        profileConfigs: <String, RemoteStorageConfig>{
          's3-profile': s3Config,
          'baidu-profile': baiduConfig,
        },
        bucketsByStorageType: const <StorageType, List<BucketInfo>>{
          StorageType.s3: <BucketInfo>[BucketInfo(name: 's3-bucket')],
          StorageType.baiduPan: <BucketInfo>[BucketInfo(name: '百度网盘')],
        },
        failingObjectStorageType: StorageType.baiduPan,
        baiduAuthorizationResult: baiduConfig.copyWith(
          accessKeyId: 'new-baidu-access',
          secretAccessKey: 'new-baidu-refresh',
        ),
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('百度网盘'));
      await tester.pumpAndSettle();
      // The object-list error view exposes a secondary action that jumps to the
      // account-management page (instead of opening an in-place editor), so the
      // user can edit, disable, or re-enable the failing account in one place.
      // The sidebar also shows "账号管理", so find the button by type+text.
      final secondaryAction = find.descendant(
        of: find.byType(ShadButton),
        matching: find.text('账号管理'),
      );
      expect(secondaryAction, findsOneWidget);
      expect(find.text('编辑账号'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('bucket list renders after its initial quota resolution', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final quota = Completer<BucketInfo>();
      final config = RemoteStorageConfig.empty().copyWith(
        endpoint: 'https://pan.baidu.com',
        storageType: StorageType.baiduPan,
        providerType: StorageProviderType.baiduPan,
        displayName: '百度账号',
        mappedBucketName: '百度网盘',
        accessKeyId: 'test-access-token',
        secretAccessKey: 'test-refresh-token',
        hasSecretAccessKey: true,
      );
      final api = _FakeApi(
        configured: true,
        configOverride: config,
        buckets: const <BucketInfo>[BucketInfo(name: '百度网盘')],
        quotaResult: quota.future,
      );

      await tester.pumpWidget(RemoteStorageApp(apiFactory: () async => api));
      await tester.pump();
      await tester.pump();
      expect(api.quotaRequestCount, 1);

      quota.complete(
        const BucketInfo(
          name: '百度网盘',
          quotaBytes: 20 * 1024 * 1024 * 1024,
          usedBytes: 7 * 1024 * 1024 * 1024,
          quotaKnown: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('7.0 GB / 20.0 GB'), findsOneWidget);
      await tester.tap(find.text('百度网盘'));
      await tester.pumpAndSettle();
      final breadcrumb = tester.widget<FileManagerBreadcrumbBar>(
        find.byType(FileManagerBreadcrumbBar),
      );
      breadcrumb.onOpenBucketList();
      await tester.pumpAndSettle();
      expect(api.quotaRequestCount, 1);
      expect(find.text('7.0 GB / 20.0 GB'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      TransferQueue.instance.resetForTest();
      RemoteTaskStore.instance.resetForTest();
      SyncProfileNotifier.instance.stop();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

final class _FakeFilePicker extends FilePickerPlatform {
  _FakeFilePicker(this.files);

  final List<PlatformFile> files;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => files;
}

/// File-picker test double that keeps the native selection future pending so a
/// bootstrap refresh can race the eventual result.
final class _PendingFilePicker extends FilePickerPlatform {
  _PendingFilePicker(this.result);

  final Future<List<PlatformFile>> result;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) => result;
}

/// Directory-picker test double used to hold a desktop directory download
/// selection open while the Android file page receives new profile inputs.
final class _PendingDirectoryPicker extends FilePickerPlatform {
  _PendingDirectoryPicker(this.result);

  final Future<String?> result;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) => result;
}

final class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile({required this.name, required this.uri});

  @override
  final String name;
  @override
  final Uri uri;

  @override
  Never get xFile => throw UnimplementedError();

  @override
  Future<int> length() async => 1;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  @override
  Stream<Uint8List> readAsByteStream() => const Stream<Uint8List>.empty();
}

/// Minimal fake API that does not need the Go bridge.
class _FakeApi implements RemoteStorageGateway {
  _FakeApi({
    required this.configured,
    this.configOverride,
    this.buckets = const <BucketInfo>[],
    this.quotaResult,
    this.profiles = const <ProfileInfo>[],
    this.profileConfigs = const <String, RemoteStorageConfig>{},
    this.bucketsByStorageType = const <StorageType, List<BucketInfo>>{},
    this.objectPagesByPrefix = const <String, ObjectListPage>{},
    this.trashPagesByToken = const <String, TrashListPage>{},
    this.failingObjectStorageType,
    this.baiduAuthorizationResult,
    this.freshBootstrapInstances = false,
  });

  final bool configured;
  final RemoteStorageConfig? configOverride;
  final List<BucketInfo> buckets;
  final Future<BucketInfo>? quotaResult;

  @override
  Future<void> validateAccountCredentials(RemoteStorageConfig config) async {}
  final List<ProfileInfo> profiles;
  final Map<String, RemoteStorageConfig> profileConfigs;
  final Map<StorageType, List<BucketInfo>> bucketsByStorageType;
  final Map<String, ObjectListPage> objectPagesByPrefix;
  final Map<String, TrashListPage> trashPagesByToken;
  final StorageType? failingObjectStorageType;
  final RemoteStorageConfig? baiduAuthorizationResult;
  final bool freshBootstrapInstances;
  Future<List<BucketInfo>>? bucketListingFuture;
  final List<Completer<List<BucketInfo>>> nextBucketListings =
      <Completer<List<BucketInfo>>>[];
  Completer<ObjectListPage>? nextObjectPage;
  final Map<String, Completer<ObjectListPage>> nextObjectPagesByPrefix =
      <String, Completer<ObjectListPage>>{};
  Completer<TrashListPage>? nextTrashPage;
  Completer<void>? nextRestoreTrashItem;
  Completer<void>? nextCreateDirectory;
  Completer<void>? nextDeleteObject;
  Completer<void>? nextRenameObject;
  Completer<void>? nextUploadFile;
  int bucketListingRequestCount = 0;
  int quotaRequestCount = 0;
  final List<String> objectPagePrefixes = <String>[];
  final List<RemoteStorageConfig> objectPageConfigs = <RemoteStorageConfig>[];
  final Map<String, RemoteStorageConfig> savedProfiles =
      <String, RemoteStorageConfig>{};
  final List<RemoteStorageConfig> createDirectoryConfigs =
      <RemoteStorageConfig>[];
  final List<RemoteStorageConfig> uploadFileConfigs = <RemoteStorageConfig>[];
  final List<RemoteStorageConfig> uploadDirectoryConfigs =
      <RemoteStorageConfig>[];
  final List<RemoteStorageConfig> downloadFileConfigs = <RemoteStorageConfig>[];
  Completer<void>? nextUploadDirectory;
  RemoteTaskPage remoteTaskPage = const RemoteTaskPage();

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async => remoteTaskPage;

  @override
  Future<RemoteTask> getRemoteTask(String taskId) async =>
      throw UnsupportedError('任务不可用');

  @override
  Future<bool> cancelRemoteTask(String taskId) async => false;

  @override
  Future<bool> retryRemoteTask(String taskId) async => false;

  @override
  Future<bool> triggerRemoteTask(String taskId) async => false;

  @override
  Future<int> triggerAllRemoteTasks({
    String profileId = '',
    String bucket = '',
  }) async => 0;

  @override
  Future<int> clearRemoteTaskHistory({
    String profileId = '',
    String bucket = '',
    List<String> taskIds = const <String>[],
  }) async => 0;

  @override
  Future<BootstrapState> loadBootstrapState() async {
    final config =
        configOverride ??
        (configured
            ? const RemoteStorageConfig(
                endpoint: 'https://s3.example.com',
                storageType: StorageType.s3,
                providerType: StorageProviderType.s3,
                displayName: 'Test Account',
                mappedBucketName: 'Test Account',
                region: 'us-east-1',
                bucket: 'test-bucket',
                accessKeyId: 'AKIA_TEST',
                secretAccessKey: 'secret_test',
                hasSecretAccessKey: true,
                webdavUsername: 'webdav-user',
                webdavPassword: '',
                hasWebdavPassword: true,
                ftpUsername: '',
                ftpPassword: '',
                hasFtpPassword: false,
                ftpPort: 0,
                ftpAnonymous: false,
                rootPrefix: '',
                defaultDownloadDirectory: '',
                cacheDirectory: '',
                resolvedCacheDirectory: '/tmp/.remote-storage/cache',
                hideDotFiles: true,
                fileOpenMode: FileOpenMode.doubleClick,
                trashDirectoryName: '.trash',
                trashRetentionDays: -1,
                bucketSettings: <String, BucketSettings>{},
                bucketViews: <String, BucketViewSettings>{},
                writebackQuietSeconds: 10,
                mountMetadataCacheSeconds: 60,
                usePathStyle: true,
                windowsMountMode: WindowsMountMode.cloudFilesCached,
                windowsThisPcEntryEnabled: false,
                windowsWritebackConcurrency: 4,
                cacheAutoCleanupEnabled: false,
                cacheMaxSizeMb: 0,
                cacheMaxAgeDays: 0,
                jwanfsGatewayMode: JWanFSGatewayMode.auto,
                proxyMode: 'system',
                proxyType: 'http',
                proxyHost: '',
                proxyPort: '',
                proxyUsername: '',
                proxyPassword: '',
              )
            : RemoteStorageConfig.empty());
    return BootstrapState(
      configPath: '/tmp/.remote-storage/config.toml',
      configured: configured,
      config: freshBootstrapInstances ? config.copyWith() : config,
      profiles: freshBootstrapInstances
          ? List<ProfileInfo>.of(profiles)
          : profiles,
    );
  }

  @override
  Future<bool> updateProxySettings({
    required String proxyMode,
    required String proxyType,
    required String proxyHost,
    required String proxyPort,
    required String proxyUsername,
    required String proxyPassword,
  }) async => true;

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async =>
      BootstrapState(
        configPath: '/tmp/.remote-storage/config.toml',
        configured: true,
        config: config,
      );

  @override
  RemoteStorageCapabilities get capabilities =>
      const RemoteStorageCapabilities.desktop();

  @override
  Future<AuthSessionState> loadAuthSession() async =>
      const AuthSessionState.desktop();

  @override
  Future<BridgeBuildInfo> getBuildInfo() async => const BridgeBuildInfo();

  @override
  Future<SystemProxyInfo?> resolveSystemProxy() async => null;

  @override
  Future<Map<String, dynamic>?> matchPlatformAsset(
    List<Map<String, dynamic>> assets, {
    String? runtimeArchitecture,
  }) async => null;

  @override
  Future<String> installApp({
    required String assetUrl,
    required String assetName,
    required int assetSize,
    required String assetDigest,
    required String installerType,
    required String mirrorPrefix,
    required RemoteStorageConfig config,
    required String proxyMode,
    required String proxyType,
    required String proxyHost,
    required String proxyPort,
    required String proxyUsername,
    required String proxyPassword,
  }) async => '';

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<String> startBaiduPanAuthorization() async =>
      throw UnimplementedError();

  @override
  Future<RemoteStorageConfig> authorizeBaiduPan(
    String displayName,
    String code,
  ) async => baiduAuthorizationResult ?? (throw UnimplementedError());

  @override
  Future<void> cleanupMounts() async {}

  @override
  Future<int> cleanupStaleWindowsProcesses() async => 0;

  @override
  Future<int> sweepOrphanMounts() async => 0;

  @override
  Future<List<BucketInfo>> listBuckets(
    RemoteStorageConfig config, {
    bool force = false,
  }) async {
    bucketListingRequestCount += 1;
    if (nextBucketListings.isNotEmpty) {
      return nextBucketListings.removeAt(0).future;
    }
    final pending = bucketListingFuture;
    if (pending != null) return await pending;
    return bucketsByStorageType[config.storageType] ?? buckets;
  }

  @override
  Future<BucketInfo> getBucketQuota(
    RemoteStorageConfig config,
    String bucket,
  ) async {
    quotaRequestCount += 1;
    return quotaResult ?? BucketInfo(name: bucket);
  }

  @override
  Future<void> saveProfile(String name, RemoteStorageConfig config) async {
    savedProfiles[name] = config;
  }

  @override
  Future<Map<String, dynamic>> deleteProfile(String name) async =>
      const <String, dynamic>{};

  @override
  Future<BootstrapState> resetUserConfig() async => BootstrapState(
    configPath: '/tmp/.remote-storage/config.toml',
    configured: false,
    config: RemoteStorageConfig.empty(),
  );

  @override
  Future<CacheStats> getCacheStats(RemoteStorageConfig config) async =>
      const CacheStats(
        path: '/tmp/.remote-storage/cache',
        exists: false,
        sizeBytes: 0,
        fileCount: 0,
        lastModified: '',
      );

  @override
  Future<void> openCacheDirectory(RemoteStorageConfig config) async {}

  @override
  Future<CleanCacheResult> cleanCache(
    RemoteStorageConfig config, {
    required bool clearAll,
  }) async => const CleanCacheResult(
    beforeBytes: 0,
    afterBytes: 0,
    removed: 0,
    freedBytes: 0,
  );

  @override
  Future<CachedFileRecord?> findCacheIndexRecord({
    required String bucket,
    required String objectKey,
  }) async => null;

  @override
  Future<void> upsertCacheIndexRecord(CachedFileRecord record) async {}

  @override
  Future<void> removeCacheIndexRecord({
    required String bucket,
    required String objectKey,
  }) async {}

  @override
  Future<List<CachedFileRecord>> removeCacheIndexPrefix({
    required String bucket,
    required String objectKeyPrefix,
  }) async => <CachedFileRecord>[];

  @override
  Future<BootstrapState> setActiveProfile(String name) async =>
      loadBootstrapState();

  @override
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async => objectPagesByPrefix[prefix]?.items ?? const <ObjectInfo>[];

  @override
  Future<ObjectListPage> listObjectPage(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String nextToken,
    int pageSize, {
    bool forceRefresh = false,
  }) async {
    objectPagePrefixes.add(prefix);
    objectPageConfigs.add(config);
    final pendingForPrefix = nextObjectPagesByPrefix.remove(prefix);
    if (pendingForPrefix != null) return pendingForPrefix.future;
    final pending = nextObjectPage;
    if (pending != null) {
      nextObjectPage = null;
      return pending.future;
    }
    if (config.storageType == failingObjectStorageType) {
      throw StateError('object listing failed');
    }
    return objectPagesByPrefix[prefix] ??
        const ObjectListPage(items: <ObjectInfo>[], nextToken: '');
  }

  @override
  Future<void> reorderProfiles(List<String> names) async {}

  @override
  Future<void> reorderBuckets(List<String> ids) async {}

  @override
  Future<List<String>> listBucketOrder() async => const <String>[];

  @override
  Future<ConfigBackupSettings> loadConfigBackupSettings() async =>
      const ConfigBackupSettings();

  @override
  Future<ConfigBackupSettings> saveConfigBackupSettings(
    ConfigBackupSettings settings,
  ) async => settings;

  @override
  Future<ConfigBackupSnapshot> backupConfigNow() async =>
      throw UnimplementedError();

  @override
  Future<List<ConfigBackupSnapshot>> listConfigBackups() async =>
      const <ConfigBackupSnapshot>[];

  @override
  Future<BootstrapState> restoreConfigBackup(String key) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteConfigBackup(String key) async =>
      throw UnimplementedError();

  @override
  Future<List<ConfigBackupSnapshot>> listConfigBackupsWithTarget(
    ConfigBackupTarget target,
  ) async => throw UnimplementedError();

  @override
  Future<BootstrapState> restoreConfigBackupWithTarget(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) async => throw UnimplementedError();

  @override
  Future<bool> verifyBackupPassword(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) async => throw UnimplementedError();

  @override
  Future<ObjectInfo> headObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
  ) async => ObjectInfo(key: key, size: 0, lastModified: '', isDir: false);

  @override
  Future<DirectoryAccess> directoryAccess(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async => const DirectoryAccess(writable: true, known: true);

  @override
  Future<void> createDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String name,
  ) async {
    createDirectoryConfigs.add(config);
    final pending = nextCreateDirectory;
    if (pending != null) {
      nextCreateDirectory = null;
      await pending.future;
    }
  }

  @override
  Future<void> deleteObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String taskId, {
    bool permanent = false,
  }) async {
    final pending = nextDeleteObject;
    if (pending != null) {
      nextDeleteObject = null;
      await pending.future;
    }
  }

  @override
  Future<List<TrashItem>> listTrash(
    RemoteStorageConfig config,
    String bucket,
  ) async => [];

  @override
  Future<TrashListPage> listTrashPage(
    RemoteStorageConfig config,
    String bucket,
    String nextToken,
    int pageSize,
  ) async {
    final pending = nextTrashPage;
    if (pending != null) {
      nextTrashPage = null;
      return pending.future;
    }
    return trashPagesByToken[nextToken] ??
        const TrashListPage(items: <TrashItem>[], nextToken: '');
  }

  @override
  Future<void> renameObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
    bool isDirectory,
    String newName, {
    String taskId = '',
  }) async {
    final pending = nextRenameObject;
    if (pending != null) {
      nextRenameObject = null;
      await pending.future;
    }
  }

  @override
  Future<void> copyObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  ) async {}

  @override
  Future<void> moveObject(
    RemoteStorageConfig config,
    String bucket,
    String sourceKey,
    String targetKey,
    bool isDirectory,
    String taskId,
  ) async {}

  @override
  Future<ShareRecord> createShare(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String name,
    int durationSec,
  ) async => const ShareRecord(
    id: 'share-id',
    bucket: 'bucket',
    key: 'file.txt',
    name: 'file.txt',
    url: 'https://example.com/share',
    expiresAt: '2026-05-27T12:00:00Z',
    durationSec: 3600,
    createdAt: '2026-05-27T11:00:00Z',
    updatedAt: '2026-05-27T11:00:00Z',
  );

  @override
  Future<List<ShareRecord>> listShares(RemoteStorageConfig config) async =>
      const [];

  @override
  Future<ShareRecord> refreshShare(
    RemoteStorageConfig config,
    String id,
    int durationSec,
  ) async => const ShareRecord(
    id: 'share-id',
    bucket: 'bucket',
    key: 'file.txt',
    name: 'file.txt',
    url: 'https://example.com/share',
    expiresAt: '2026-05-27T12:00:00Z',
    durationSec: 3600,
    createdAt: '2026-05-27T11:00:00Z',
    updatedAt: '2026-05-27T11:00:00Z',
  );

  @override
  Future<void> deleteShare(RemoteStorageConfig config, String id) async {}

  @override
  Future<void> restoreTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId, {
    String originalKey = '',
    bool isDirectory = false,
  }) async {
    final pending = nextRestoreTrashItem;
    if (pending != null) {
      nextRestoreTrashItem = null;
      await pending.future;
    }
  }

  @override
  Future<void> deleteTrashItem(
    RemoteStorageConfig config,
    String bucket,
    String trashId,
  ) async {}

  @override
  Future<void> clearTrash(RemoteStorageConfig config, String bucket) async {}

  @override
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {
    uploadFileConfigs.add(config);
    final pending = nextUploadFile;
    if (pending != null) {
      nextUploadFile = null;
      await pending.future;
    }
  }

  @override
  Future<void> uploadDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String localPath,
    String taskId,
  ) async {
    uploadDirectoryConfigs.add(config);
    final pending = nextUploadDirectory;
    if (pending != null) {
      nextUploadDirectory = null;
      await pending.future;
    }
  }

  @override
  Future<void> uploadBytes(
    RemoteStorageConfig config,
    String bucket,
    String key,
    Uint8List bytes,
    String taskId, {
    String fileName = '',
  }) async {}

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) async {
    downloadFileConfigs.add(config);
  }

  @override
  Uri? objectDownloadUri(String bucket, String key, {bool inline = false}) =>
      null;

  @override
  Uri? webDavUri(String bucket) => null;

  @override
  Future<void> cancelTransfer(String taskId) async {}

  @override
  Future<bool> triggerTransfer(String taskId) async => false;

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async =>
      profileConfigs[name] ?? configOverride ?? RemoteStorageConfig.empty();

  @override
  Future<List<ProfileInfo>> listProfiles() async => [];

  @override
  Future<List<TransferSnapshot>> listTransferJobs() async => [];

  @override
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
    MountBucketOptions options,
  ) async => const BucketMountStatus(
    mounted: false,
    bucket: '',
    mountPath: '',
    serverUrl: '',
    port: 0,
  );

  @override
  Future<BucketMountStatus> unmountBucket(
    String bucket, {
    bool removeLocalCache = false,
  }) async => const BucketMountStatus(
    mounted: false,
    bucket: '',
    mountPath: '',
    serverUrl: '',
    port: 0,
  );

  @override
  Future<BucketMountStatus> getBucketMountStatus(String bucket) async =>
      const BucketMountStatus(
        mounted: false,
        bucket: '',
        mountPath: '',
        serverUrl: '',
        port: 0,
      );

  @override
  Future<BucketMountStatus> openBucketMount(String bucket) async =>
      const BucketMountStatus(
        mounted: false,
        bucket: '',
        mountPath: '',
        serverUrl: '',
        port: 0,
      );

  // --- Directory sync stubs ---

  @override
  Future<List<SyncProfileRuntime>> listSyncProfiles() async =>
      <SyncProfileRuntime>[];

  @override
  Future<String> saveSyncProfile(SyncProfile profile) async => '';

  @override
  Future<void> deleteSyncProfile(String id) async {}

  @override
  Future<void> setLogLevel(String level) async {}

  @override
  Future<void> writeAppLog(
    String message, {
    String level = 'info',
    String tag = 'flutter',
  }) async {}

  @override
  Future<int> triggerSyncProfile(String id) async => 0;

  @override
  Future<Map<String, dynamic>> getP2PStatus() async =>
      throw UnsupportedError('P2P 不可用');

  @override
  Future<void> setP2PEnabled(bool enabled) async =>
      throw UnsupportedError('P2P 不可用');
}
