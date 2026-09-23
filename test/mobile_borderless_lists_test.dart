// Android 无边框基线回归：文件管理页（参照页）在移动端不套带边框的卡片，
// 其余底栏页的列表/卡片容器已对齐该基线；桌面端卡片外观保持不变。
// 平台分支通过 debugDefaultTargetPlatformOverride 驱动（binding 规则），
// try/finally 内复位。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/widgets/cloud_storage_account_list.dart';
import 'package:remote_storage/widgets/file_manager_trash_browser.dart';
import 'package:remote_storage/widgets/global_trash_browser.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const TrashItem _sampleTrashItem = TrashItem(
  id: 't1',
  name: 'report.txt',
  originalKey: 'docs/report.txt',
  trashKey: 'trash/docs/report.txt',
  deletedAt: '2026-09-01 10:00',
  isDir: false,
  size: 24,
  objectCount: 1,
);

const ProfileInfo _sampleProfile = ProfileInfo(
  name: 'profile',
  displayName: '测试账号',
  storageType: StorageType.s3,
  providerType: StorageProviderType.s3,
  endpoint: 'https://s3.example.com',
  accessKeyId: 'AKIA_TEST',
);

Widget _wrap(Widget child) => ShadApp(home: Material(child: child));

void main() {
  testWidgets('bucket trash list drops its card border on Android only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        _wrap(
          FileManagerTrashBrowser(
            items: const [_sampleTrashItem],
            isGrid: false,
            scrollController: ScrollController(),
            hasMore: false,
            loadingMore: false,
            onRestore: (_) {},
            onDeletePermanently: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('report.txt'), findsOneWidget);
      expect(find.byType(ShadCard), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    }
    // 桌面（含上面的 macOS 复位值）保持带边框卡片的原外观。
    try {
      await tester.pumpWidget(
        _wrap(
          FileManagerTrashBrowser(
            items: const [_sampleTrashItem],
            isGrid: false,
            scrollController: ScrollController(),
            hasMore: false,
            loadingMore: false,
            onRestore: (_) {},
            onDeletePermanently: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ShadCard), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('global trash list drops its card border on Android only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        _wrap(
          GlobalTrashBrowser(
            entries: const [
              GlobalTrashBrowserEntry(bucket: 'bucket', item: _sampleTrashItem),
            ],
            scrollController: ScrollController(),
            loadingMore: false,
            selectedIds: const <String>{},
            busyIds: const <String>{},
            showBucketColumn: false,
            onToggleSelection: (_) {},
            onToggleSelectAll: () {},
            onRestore: (_) {},
            onDeletePermanently: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('report.txt'), findsOneWidget);
      expect(find.byType(ShadCard), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    }
    try {
      await tester.pumpWidget(
        _wrap(
          GlobalTrashBrowser(
            entries: const [
              GlobalTrashBrowserEntry(bucket: 'bucket', item: _sampleTrashItem),
            ],
            scrollController: ScrollController(),
            loadingMore: false,
            selectedIds: const <String>{},
            busyIds: const <String>{},
            showBucketColumn: false,
            onToggleSelection: (_) {},
            onToggleSelectAll: () {},
            onRestore: (_) {},
            onDeletePermanently: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ShadCard), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('account mobile list keeps its card, desktop table keeps one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 400,
            child: CloudStorageAccountList(
              accounts: const [_sampleProfile],
              isGrid: false,
              mobileLayout: true,
              busy: false,
              onEdit: (_) {},
              onDelete: (_) {},
              onManageBuckets: (_) {},
              onToggleDisabled: (_, _) {},
              status: const <String, AccountStatus>{},
              statusError: const <String, String>{},
              onReorder: null,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('测试账号'), findsOneWidget);
      // 账号块卡片已按用户裁决恢复（无边框基线仅适用于文件/回收站/任务）。
      expect(find.byType(ShadCard), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    }
    try {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 400,
            child: CloudStorageAccountList(
              accounts: const [_sampleProfile],
              isGrid: false,
              mobileLayout: false,
              busy: false,
              onEdit: (_) {},
              onDelete: (_) {},
              onManageBuckets: (_) {},
              onToggleDisabled: (_, _) {},
              status: const <String, AccountStatus>{},
              statusError: const <String, String>{},
              onReorder: null,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('测试账号'), findsOneWidget);
      expect(find.byType(ShadCard), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
