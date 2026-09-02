import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('Android app tooltip exposes semantics without a touch tooltip', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShadApp(
          home: Material(
            child: AppTooltip(
              message: '返回',
              child: const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      );

      expect(find.byType(ShadTooltip), findsNothing);
      expect(find.bySemanticsLabel('返回'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop app tooltip keeps its visual hint', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        ShadApp(
          home: Material(
            child: AppTooltip(
              message: '返回',
              child: const SizedBox(width: 32, height: 32),
            ),
          ),
        ),
      );

      expect(find.byType(ShadTooltip), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
