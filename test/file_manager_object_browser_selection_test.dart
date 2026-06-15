// File manager object browser tests cover desktop selection gestures around the list header.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/file_manager_drag_selection.dart';
import 'package:remote_storage/widgets/file_manager_object_browser.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'header select-all toggles off instead of clearing then reselecting',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final objects = <ObjectInfo>[
        const ObjectInfo(key: 'photos/default.png', size: 1024, isDir: false),
        const ObjectInfo(key: 'photos/garage.png', size: 2048, isDir: false),
      ];
      final selectedKeys = <String>{};

      await tester.pumpWidget(
        ShadApp(
          home: Material(
            child: StatefulBuilder(
              builder: (context, setState) {
                void toggleSelection(ObjectInfo object) {
                  setState(() {
                    if (!selectedKeys.add(object.key)) {
                      selectedKeys.remove(object.key);
                    }
                  });
                }

                void toggleSelectAll() {
                  final keys = objects.map((object) => object.key).toSet();
                  final hasUnselected = keys.any(
                    (key) => !selectedKeys.contains(key),
                  );
                  setState(() {
                    if (hasUnselected) {
                      selectedKeys.addAll(keys);
                    } else {
                      selectedKeys.removeAll(keys);
                    }
                  });
                }

                return SizedBox(
                  width: 900,
                  height: 600,
                  child: FileManagerObjectBrowser(
                    objects: objects,
                    prefix: 'photos/',
                    isGrid: false,
                    scrollController: ScrollController(),
                    hasMore: false,
                    loadingMore: false,
                    selectedKeys: selectedKeys,
                    deletingKeys: const <String>{},
                    gridIconSize: 44,
                    listIconSize: 34,
                    onOpenDirectory: (_) {},
                    onOpenFile: (_) {},
                    onDownloadFile: (_) {},
                    onNavigateUp: () {},
                    onToggleSelection: toggleSelection,
                    onSelectionSetChanged: (keys) {
                      setState(() {
                        selectedKeys
                          ..clear()
                          ..addAll(keys);
                      });
                    },
                    onToggleSelectAll: toggleSelectAll,
                    onClearSelection: () {
                      setState(selectedKeys.clear);
                    },
                    onObjectAction: (_, _) {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final headerControl = find.byType(ListSelectionControl).first;

      await tester.tap(headerControl, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(selectedKeys, containsAll(objects.map((object) => object.key)));

      await tester.tap(headerControl, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(selectedKeys, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('clicking a directory in selection mode toggles selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final objects = <ObjectInfo>[
      const ObjectInfo(key: 'photos/default.png', size: 1024, isDir: false),
      const ObjectInfo(key: 'photos/album/', size: 0, isDir: true),
    ];
    final selectedKeys = <String>{'photos/default.png'};
    var openedDirectoryCount = 0;

    await tester.pumpWidget(
      ShadApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) {
              void toggleSelection(ObjectInfo object) {
                setState(() {
                  if (!selectedKeys.add(object.key)) {
                    selectedKeys.remove(object.key);
                  }
                });
              }

              return SizedBox(
                width: 900,
                height: 600,
                child: FileManagerObjectBrowser(
                  objects: objects,
                  prefix: '',
                  isGrid: false,
                  scrollController: ScrollController(),
                  hasMore: false,
                  loadingMore: false,
                  selectedKeys: selectedKeys,
                  deletingKeys: const <String>{},
                  gridIconSize: 44,
                  listIconSize: 34,
                  onOpenDirectory: (_) => openedDirectoryCount++,
                  onOpenFile: (_) {},
                  onDownloadFile: (_) {},
                  onNavigateUp: () {},
                  onToggleSelection: toggleSelection,
                  onSelectionSetChanged: (keys) {
                    setState(() {
                      selectedKeys
                        ..clear()
                        ..addAll(keys);
                    });
                  },
                  onToggleSelectAll: () {},
                  onClearSelection: () {
                    setState(selectedKeys.clear);
                  },
                  onObjectAction: (_, _) {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('album'), kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(openedDirectoryCount, 0);
    expect(selectedKeys, contains('photos/album/'));

    await tester.tap(find.text('album'), kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(openedDirectoryCount, 0);
    expect(selectedKeys, isNot(contains('photos/album/')));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'drag selection toggles intersected items into existing selection',
    (tester) async {
      final selectedKeys = <String>{'a', 'outside'};

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  height: 180,
                  child: FileManagerDragSelection(
                    enabled: true,
                    selectedKeys: selectedKeys,
                    onSelectionChanged: (keys) {
                      setState(() {
                        selectedKeys
                          ..clear()
                          ..addAll(keys);
                      });
                    },
                    child: Stack(
                      children: const [
                        _DragSelectionBox(selectionKey: 'a', left: 50),
                        _DragSelectionBox(selectionKey: 'b', left: 120),
                        _DragSelectionBox(selectionKey: 'outside', left: 240),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(const Offset(20, 20));
      await gesture.moveTo(const Offset(190, 110));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(selectedKeys, unorderedEquals(<String>{'b', 'outside'}));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('drag selection keeps touched items toggled after scrolling', (
    tester,
  ) async {
    final selectedKeys = <String>{'a', 'outside'};
    var scrolled = false;
    StateSetter? updateLayout;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateLayout = setState;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: 180,
                child: FileManagerDragSelection(
                  enabled: true,
                  selectedKeys: selectedKeys,
                  onSelectionChanged: (keys) {
                    setState(() {
                      selectedKeys
                        ..clear()
                        ..addAll(keys);
                    });
                  },
                  child: Stack(
                    children: [
                      if (!scrolled)
                        const _DragSelectionBox(selectionKey: 'a', left: 50),
                      _DragSelectionBox(
                        selectionKey: 'b',
                        left: scrolled ? 120 : 240,
                      ),
                      const _DragSelectionBox(
                        selectionKey: 'outside',
                        left: 280,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(const Offset(20, 20));
    await gesture.moveTo(const Offset(100, 110));
    await tester.pump();
    expect(selectedKeys, unorderedEquals(<String>{'outside'}));

    updateLayout?.call(() => scrolled = true);
    await tester.pump();
    await gesture.moveTo(const Offset(190, 110));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectedKeys, unorderedEquals(<String>{'b', 'outside'}));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _DragSelectionBox extends StatelessWidget {
  const _DragSelectionBox({required this.selectionKey, required this.left});

  final String selectionKey;
  final double left;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: 50,
      width: 40,
      height: 40,
      child: FileManagerDragSelectionTarget(
        selectionKey: selectionKey,
        enabled: true,
        child: ColoredBox(color: Colors.blue),
      ),
    );
  }
}
