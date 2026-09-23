import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:remote_storage/widgets/file_manager_object_header.dart';
import 'package:remote_storage/widgets/desktop_context_menu_region.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:remote_storage/widgets/mobile_selection_chrome.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  // 两态选择模型下的 Android 对象行契约:浏览态行尾选择圆点、无行首
  // 控件、行点击/长按分别是打开与进入选中;选中态行首 48dp 勾选控件、
  // 圆点隐藏。行级动作在页面的选中态底部动作条,不再有每行 `…` 抽屉。

  testWidgets(
    'Android browse rows open on tap and select via dot or long-press',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        var openedFiles = 0;
        var selectionTaps = 0;

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

        expect(find.byType(ShadCard), findsNothing);
        expect(find.byType(FileManagerObjectHeader), findsNothing);
        final row = tester.widget<FileListTile>(find.byType(FileListTile));
        expect(row.compact, isTrue);
        // 浏览态:无行首选择控件,行尾是 48dp 选择圆点。
        expect(row.showSelectionControl, isFalse);
        final dot = find.descendant(
          of: find.byType(FileListTile),
          matching: find.byType(MobileRowSelectDot),
        );
        expect(dot, findsOneWidget);
        expect(tester.getSize(dot), const Size(48, 48));
        expect(
          find.descendant(
            of: find.byType(FileListTile),
            matching: find.byIcon(LucideIcons.ellipsisVertical),
          ),
          findsNothing,
        );
        expect(find.byType(DesktopContextMenuRegion), findsNothing);

        // 行点击仍是主操作(打开文件);圆点与长按进入选中。
        await tester.tap(find.byType(FileListTile));
        await tester.pump();
        expect(openedFiles, 1);
        expect(selectionTaps, 0);

        await tester.tap(dot);
        await tester.pump();
        expect(selectionTaps, 1);

        await tester.longPress(find.byType(FileListTile));
        await tester.pump();
        expect(selectionTaps, 2);
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
    'Android browse rows keep the dot inside narrow, tall text layouts',
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

        expect(
          find.descendant(
            of: find.byType(FileListTile),
            matching: find.byType(MobileRowSelectDot),
          ),
          findsOneWidget,
        );
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
    'Android selection state shows the leading control and hides dots',
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

        // 选中态:行首 48dp 勾选控件接管,行尾圆点消失。
        final control = find.byType(ListSelectionControl).first;
        expect(tester.getSize(control), const Size(48, 48));
        expect(
          find.descendant(
            of: find.byType(FileListTile),
            matching: find.byType(MobileRowSelectDot),
          ),
          findsNothing,
        );
        final controlRect = tester.getRect(control);
        await tester.tapAt(controlRect.topLeft + const Offset(2, 2));
        expect(selectionTaps, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets('parent and deleting rows hide the select dot', (tester) async {
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
              scrollController: ScrollController(),
              hasMore: false,
              loadingMore: false,
              selectedKeys: const <String>{},
              deletingKeys: const <String>{'locked.txt'},
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

      expect(
        find.descendant(
          of: find.byType(FileListTile),
          matching: find.byType(MobileRowSelectDot),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
