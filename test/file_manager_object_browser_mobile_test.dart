import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:remote_storage/widgets/file_manager_object_header.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'Android object list uses compact rows and a bottom action sheet',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        var openedFiles = 0;

        await tester.pumpWidget(
          ShadApp(
            home: Material(
              child: FileManagerObjectBrowser(
                objects: const [
                  ObjectInfo(
                    key: 'notes.txt',
                    size: 24,
                    lastModified: '2026-08-31',
                    isDir: false,
                  ),
                ],
                prefix: '',
                isGrid: false,
                mobilePresentation: true,
                scrollController: ScrollController(),
                hasMore: false,
                loadingMore: false,
                selectedKeys: const <String>{},
                deletingKeys: const <String>{},
                gridIconSize: 44,
                listIconSize: 34,
                onOpenDirectory: (_) {},
                onOpenFile: (_) => openedFiles++,
                onDownloadFile: (_) {},
                onNavigateUp: () {},
                onToggleSelection: (_) {},
                onSelectionSetChanged: (_) {},
                onToggleSelectAll: () {},
                onClearSelection: () {},
                onSelectionAction: (_) {},
                onObjectAction: (_, _) {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ShadCard), findsNothing);
        expect(find.byType(FileManagerObjectHeader), findsNothing);
        final row = tester.widget<FileListTile>(find.byType(FileListTile));
        expect(row.compact, isTrue);
        expect(tester.widget<Text>(find.text('notes.txt')).style?.fontSize, 14);
        expect(tester.widget<Text>(find.text('24 B')).style?.fontSize, 12);
        expect(
          tester.widget<Text>(find.text('2026-08-31')).style?.fontSize,
          12,
        );
        expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);
        expect(
          tester.getSize(find.byIcon(LucideIcons.ellipsisVertical)),
          const Size(18, 18),
        );
        final button = find.ancestor(
          of: find.byIcon(LucideIcons.ellipsisVertical),
          matching: find.byType(ShadIconButton),
        );
        expect(tester.getSize(button), const Size(48, 48));
        expect(find.byType(DesktopContextMenuRegion), findsNothing);
        expect(find.bySemanticsLabel('notes.txt 的更多操作'), findsOneWidget);

        await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
        await tester.pumpAndSettle();
        expect(openedFiles, 0);
        expect(find.byType(AppShadDialog), findsOneWidget);
        expect(find.text('预览'), findsOneWidget);
        expect(find.text('下载'), findsOneWidget);
        expect(find.text('创建分享'), findsOneWidget);
        expect(find.text('复制到...'), findsOneWidget);
        expect(find.text('移动到...'), findsOneWidget);
        expect(find.text('重命名'), findsOneWidget);
        expect(find.text('删除'), findsOneWidget);

        // The dialog close affordance is also a ShadButton; action labels are
        // the stable way to select the seven menu rows.
        const actionLabels = [
          '预览',
          '下载',
          '创建分享',
          '复制到...',
          '移动到...',
          '重命名',
          '删除',
        ];
        for (final label in actionLabels) {
          final actionButton = find.ancestor(
            of: find.text(label),
            matching: find.byType(ShadButton),
          );
          expect(actionButton, findsOneWidget);
          expect(tester.getSize(actionButton).height, greaterThanOrEqualTo(48));
        }

        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(AppShadDialog), findsNothing);

        await tester.longPress(find.byType(FileListTile));
        await tester.pumpAndSettle();
        expect(find.text('重命名'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets(
    'Android object action sheet survives narrow, tall text layouts',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(260, 420);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ShadApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Material(
                child: FileManagerObjectBrowser(
                  objects: const [
                    ObjectInfo(
                      key: 'a-very-long-file-name-for-narrow-screen.txt',
                      size: 24,
                      lastModified: '2026-08-31 12:34',
                      isDir: false,
                    ),
                  ],
                  prefix: '',
                  isGrid: false,
                  mobilePresentation: true,
                  scrollController: ScrollController(),
                  hasMore: false,
                  loadingMore: false,
                  selectedKeys: const <String>{},
                  deletingKeys: const <String>{},
                  gridIconSize: 44,
                  listIconSize: 34,
                  onOpenDirectory: (_) {},
                  onOpenFile: (_) {},
                  onDownloadFile: (_) {},
                  onNavigateUp: () {},
                  onToggleSelection: (_) {},
                  onSelectionSetChanged: (_) {},
                  onToggleSelectAll: () {},
                  onClearSelection: () {},
                  onSelectionAction: (_) {},
                  onObjectAction: (_, _) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
        await tester.pumpAndSettle();
        expect(find.byType(AppShadDialog), findsOneWidget);
        expect(tester.takeException(), isNull);

        // The action list is scrollable when the sheet cannot fit every row.
        final actionList = find.byType(SingleChildScrollView);
        expect(actionList, findsAtLeastNWidgets(1));
        await tester.ensureVisible(find.text('删除'));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets(
    'Android object selection keeps a 48dp target and gates directory downloads',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        var selectionTaps = 0;
        await tester.pumpWidget(
          ShadApp(
            home: Material(
              child: FileManagerObjectBrowser(
                objects: const [
                  ObjectInfo(key: 'docs/a/', size: 0, isDir: true),
                  ObjectInfo(key: 'docs/b/', size: 0, isDir: true),
                ],
                prefix: 'docs/',
                isGrid: false,
                mobilePresentation: true,
                scrollController: ScrollController(),
                hasMore: false,
                loadingMore: false,
                selectedKeys: const {'docs/a/', 'docs/b/'},
                deletingKeys: const <String>{},
                supportsDirectoryDownload: false,
                supportsBrowserTransfers: false,
                gridIconSize: 44,
                listIconSize: 34,
                onOpenDirectory: (_) {},
                onOpenFile: (_) {},
                onDownloadFile: (_) {},
                onNavigateUp: () {},
                onToggleSelection: (_) => selectionTaps++,
                onSelectionSetChanged: (_) {},
                onToggleSelectAll: () {},
                onClearSelection: () {},
                onSelectionAction: (_) {},
                onObjectAction: (_, _) {},
              ),
            ),
          ),
        );
        await tester.pump();

        final control = find.byType(ListSelectionControl).first;
        expect(tester.getSize(control), const Size(48, 48));
        final controlRect = tester.getRect(control);
        await tester.tapAt(controlRect.topLeft + const Offset(2, 2));
        expect(selectionTaps, 1);

        await tester.tap(find.byIcon(LucideIcons.ellipsisVertical).first);
        await tester.pumpAndSettle();
        expect(find.byType(AppShadDialog), findsOneWidget);
        expect(find.text('已选 2 项'), findsOneWidget);
        expect(find.text('批量下载'), findsNothing);
        expect(find.text('批量复制到...'), findsOneWidget);
        expect(find.text('批量移动到...'), findsOneWidget);
        expect(find.text('批量删除'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets('Android read-only object sheet omits write actions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ShadApp(
          home: Material(
            child: FileManagerObjectBrowser(
              objects: const [
                ObjectInfo(key: 'locked.txt', size: 24, isDir: false),
              ],
              prefix: '',
              isGrid: false,
              mobilePresentation: true,
              readOnly: true,
              scrollController: ScrollController(),
              hasMore: false,
              loadingMore: false,
              selectedKeys: const <String>{},
              deletingKeys: const <String>{},
              gridIconSize: 44,
              listIconSize: 34,
              onOpenDirectory: (_) {},
              onOpenFile: (_) {},
              onDownloadFile: (_) {},
              onNavigateUp: () {},
              onToggleSelection: (_) {},
              onSelectionSetChanged: (_) {},
              onToggleSelectAll: () {},
              onClearSelection: () {},
              onSelectionAction: (_) {},
              onObjectAction: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
      await tester.pumpAndSettle();

      expect(find.text('预览'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);
      expect(find.text('创建分享'), findsOneWidget);
      expect(find.text('复制到...'), findsNothing);
      expect(find.text('移动到...'), findsNothing);
      expect(find.text('重命名'), findsNothing);
      expect(find.text('删除'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('Android batch sheet keeps eligible files with blocked folders', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ShadApp(
          home: Material(
            child: FileManagerObjectBrowser(
              objects: const [
                ObjectInfo(key: 'report.txt', size: 24, isDir: false),
                ObjectInfo(key: 'archive/', size: 0, isDir: true),
              ],
              prefix: '',
              isGrid: false,
              mobilePresentation: true,
              scrollController: ScrollController(),
              hasMore: false,
              loadingMore: false,
              selectedKeys: const <String>{'report.txt', 'archive/'},
              deletingKeys: const <String>{},
              supportsDirectoryDownload: false,
              supportsBrowserTransfers: false,
              gridIconSize: 44,
              listIconSize: 34,
              onOpenDirectory: (_) {},
              onOpenFile: (_) {},
              onDownloadFile: (_) {},
              onNavigateUp: () {},
              onToggleSelection: (_) {},
              onSelectionSetChanged: (_) {},
              onToggleSelectAll: () {},
              onClearSelection: () {},
              onSelectionAction: (_) {},
              onObjectAction: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.ellipsisVertical).first);
      await tester.pumpAndSettle();

      expect(find.text('已选 2 项'), findsOneWidget);
      expect(find.text('批量下载'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
