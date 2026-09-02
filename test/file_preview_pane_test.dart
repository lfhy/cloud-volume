// Markdown preview rendering stays separate from file-manager transfer wiring.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/widgets/file_preview_pane.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('Markdown files render inside the file preview pane', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        ShadApp(
          home: Material(
            child: SizedBox(
              height: 500,
              child: FilePreviewPane(
                kind: FilePreviewKind.markdown,
                source: FilePreviewSource(
                  bytes: Uint8List.fromList(
                    utf8.encode('# 使用说明\n\n这是 **Markdown** 预览。'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.bySemanticsLabel('Markdown 预览'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Markdown images never create remote or local image loaders', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        ShadApp(
          home: Material(
            child: SizedBox(
              height: 500,
              child: FilePreviewPane(
                kind: FilePreviewKind.markdown,
                source: FilePreviewSource(
                  bytes: Uint8List.fromList(
                    utf8.encode(
                      '![远程图片](https://example.invalid/preview.png)\n\n'
                      '![本地图片](file:///private/preview.png)',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('（图片未加载）'), findsNWidgets(2));
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
