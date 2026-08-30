// Object action dialog helpers keep selected folders separate from object keys.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  const file = ObjectInfo(key: 'source/report.txt', size: 10, isDir: false);

  test('builds a target key from the selected remote directory', () {
    expect(
      objectTargetPathInDirectory('archive/2026/', file),
      'archive/2026/report.txt',
    );
    expect(objectTargetPathInDirectory('', file), 'report.txt');
  });

  testWidgets('clear-trash actions wrap on narrow Android with large text', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(240, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    try {
      await tester.pumpWidget(
        ShadApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ShadButton(
                onPressed: () => showClearTrashDialog(context, 'backup-root'),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      final cancel = tester.getRect(find.widgetWithText(ShadButton, '取消'));
      final confirm = tester.getRect(find.widgetWithText(ShadButton, '清空回收站'));
      expect(confirm.top, greaterThan(cancel.top));
      expect(cancel.left, greaterThanOrEqualTo(0));
      expect(cancel.right, lessThanOrEqualTo(240));
      expect(confirm.left, greaterThanOrEqualTo(0));
      expect(confirm.right, lessThanOrEqualTo(240));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
