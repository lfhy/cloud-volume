// App modal tests pin Android fullscreen chrome and desktop dialog sizing.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:remote_storage/widgets/file_preview_dialog.dart';
import 'package:remote_storage/widgets/file_preview_pane.dart';
import 'package:remote_storage/widgets/file_sync_profile_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _surfaceColor = Color(0xfffefdfc);

void main() {
  testWidgets(
    'Android app modal surface fills the viewport behind safe areas',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        _configureView(
          tester,
          size: const Size(393, 852),
          padding: const FakeViewPadding(top: 24, bottom: 34),
        );

        await _pumpHost(tester, nested: true);
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();

        final surfaceRect = tester.getRect(_surfaceFinder());
        expect(surfaceRect, const Rect.fromLTWH(0, 0, 393, 852));
        expect(
          find.descendant(
            of: find.byType(AppShadDialog),
            matching: find.byType(SafeArea),
          ),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(find.text('Android 全屏')).dy,
          greaterThanOrEqualTo(24),
        );
        final systemUiRegion = find.ancestor(
          of: find.byType(AppShadDialog),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        );
        final systemUiStyle = tester
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(systemUiRegion)
            .value;
        expect(systemUiStyle.statusBarIconBrightness, Brightness.dark);
        expect(
          systemUiStyle.systemNavigationBarIconBrightness,
          Brightness.dark,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byIcon(LucideIcons.x));
        await tester.pumpAndSettle();
        expect(find.text('Android 全屏'), findsNothing);
        expect(systemUiRegion, findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android modal fills only the keyboard-available viewport', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      _configureView(
        tester,
        size: const Size(393, 852),
        viewInsets: const FakeViewPadding(bottom: 300),
      );

      await _pumpHost(tester);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(_surfaceFinder()),
        const Rect.fromLTWH(0, 0, 393, 552),
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop app modal remains constrained and centered', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      _configureView(tester, size: const Size(1280, 800));

      await _pumpHost(tester);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      final surfaceRect = tester.getRect(_surfaceFinder());
      expect(surfaceRect.width, lessThanOrEqualTo(240));
      expect(surfaceRect.width, lessThan(1280));
      expect(surfaceRect.height, lessThan(800));
      expect(surfaceRect.center.dx, closeTo(640, .5));
      expect(surfaceRect.center.dy, closeTo(400, .5));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop sync navigation remains trailing aligned', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      _configureView(tester, size: const Size(1000, 700));
      await tester.pumpWidget(
        ShadApp(
          home: FileSyncProfileEditor(
            api: _FakeGateway(),
            buckets: const [],
            onSave: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final editorRect = tester.getRect(find.byType(FileSyncProfileEditor));
      final nextRect = tester.getRect(find.widgetWithText(ShadButton, '下一步'));
      expect(nextRect.center.dx, greaterThan(editorRect.center.dx));
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android system back closes only the modal route', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      _configureView(tester, size: const Size(393, 852));
      Object? result = 'pending';

      await _pumpHost(tester, onResult: (value) => result = value);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('Android 全屏'), findsNothing);
      expect(find.text('底层页面'), findsOneWidget);
      expect(result, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'backup storage editor also uses the Android fullscreen surface',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        _configureView(
          tester,
          size: const Size(393, 852),
          padding: const FakeViewPadding(top: 24, bottom: 34),
        );
        await tester.pumpWidget(
          ShadApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ShadButton(
                  onPressed: () => showAppModal<void>(
                    context: context,
                    builder: (_) => CloudStorageAccountDialog(
                      api: _FakeGateway(),
                      simpleMode: true,
                      onSave: (_) async => true,
                      onStartBaiduPanAuthorization: () async => '',
                      onAuthorizeBaiduPan: (_, _) async =>
                          RemoteStorageConfig.empty(),
                      onListBuckets: (_) async => const <BucketInfo>[],
                    ),
                  ),
                  child: const Text('配置备份'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('配置备份'));
        await tester.pumpAndSettle();

        expect(find.text('配置独立备份存储'), findsOneWidget);
        final expandedSurface = find.descendant(
          of: find.byType(CloudStorageAccountDialog),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                widget.constraints == const BoxConstraints.expand(),
          ),
        );
        expect(
          tester.getRect(expandedSurface),
          const Rect.fromLTWH(0, 0, 393, 852),
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android scrollable modal keeps the SFTP focus ring inside its viewport',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        _configureView(
          tester,
          size: const Size(393, 852),
          padding: const FakeViewPadding(top: 24, bottom: 34),
        );
        await tester.pumpWidget(
          ShadApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ShadButton(
                  onPressed: () => showAppModal<void>(
                    context: context,
                    builder: (_) => CloudStorageAccountDialog(
                      api: _FakeGateway(),
                      simpleMode: true,
                      onSave: (_) async => true,
                      onStartBaiduPanAuthorization: () async => '',
                      onAuthorizeBaiduPan: (_, _) async =>
                          RemoteStorageConfig.empty(),
                      onListBuckets: (_) async => const <BucketInfo>[],
                    ),
                  ),
                  child: const Text('配置备份'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('配置备份'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(StorageProtocolCard),
            matching: find.text('SFTP'),
          ),
        );
        await tester.tap(find.widgetWithText(ShadButton, '下一步'));
        await tester.pumpAndSettle();

        final addressLabel = find.text('SFTP 地址');
        final addressInput = find.ancestor(
          of: find.text('host 或 sftp://host'),
          matching: find.byType(ShadInput),
        );
        final addressEditable = find.descendant(
          of: addressInput,
          matching: find.byType(EditableText),
        );
        final outerScroll = find.ancestor(
          of: addressLabel,
          matching: find.byType(SingleChildScrollView),
        );

        await tester.showKeyboard(addressEditable);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();

        final scrollRect = tester.getRect(outerScroll);
        final inputRect = tester.getRect(addressInput);
        final portRect = tester.getRect(find.text('端口'));
        const focusRingExtent = 4.0;
        expect(
          inputRect.left - scrollRect.left,
          greaterThanOrEqualTo(focusRingExtent),
        );
        expect(
          scrollRect.right - inputRect.right,
          greaterThanOrEqualTo(focusRingExtent),
        );
        expect(portRect.top - inputRect.bottom, greaterThanOrEqualTo(14));
        expect(portRect.top, greaterThanOrEqualTo(scrollRect.top + 4));
        expect(portRect.bottom, lessThanOrEqualTo(scrollRect.bottom - 4));
        expect(
          tester.widget<EditableText>(addressEditable).focusNode.hasFocus,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('sync editor uses a bounded fill-height Android layout', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      _configureView(tester, size: const Size(360, 640));
      await tester.pumpWidget(
        ShadApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: FileSyncProfileEditor(
                api: _FakeGateway(),
                buckets: const [],
                onSave: (_) async => true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expandedSurface = find.descendant(
        of: find.byType(FileSyncProfileEditor),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              widget.constraints == const BoxConstraints.expand(),
        ),
      );
      expect(tester.getSize(expandedSurface), const Size(360, 640));
      expect(find.text('本地目录'), findsOneWidget);
      expect(find.text('远端目录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'sync editor stays scrollable in Android landscape with the keyboard',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        _configureView(
          tester,
          size: const Size(800, 360),
          padding: const FakeViewPadding(top: 24, bottom: 20),
        );
        await tester.pumpWidget(
          ShadApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: FileSyncProfileEditor(
                  api: _FakeGateway(),
                  buckets: const [],
                  onSave: (_) async => true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.showKeyboard(find.byType(EditableText).first);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).first)
              .focusNode
              .hasFocus,
          isTrue,
        );
        final nextButton = find.widgetWithText(ShadButton, '下一步');
        await tester.ensureVisible(nextButton);
        await tester.pumpAndSettle();
        final expandedSurface = find.descendant(
          of: find.byType(FileSyncProfileEditor),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                widget.constraints == const BoxConstraints.expand(),
          ),
        );
        final surfaceRect = tester.getRect(expandedSurface.first);
        final nextButtonRect = tester.getRect(nextButton);
        expect(nextButtonRect.top, greaterThanOrEqualTo(surfaceRect.top + 24));
        expect(
          nextButtonRect.bottom,
          lessThanOrEqualTo(surfaceRect.bottom - 20),
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('file preview fills Android height and wraps four actions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      _configureView(tester, size: const Size(360, 640));
      await tester.pumpWidget(
        ShadApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: FilePreviewDialog(
                object: const ObjectInfo(
                  key: 'documents/a-very-long-report-name.bin',
                  size: 42,
                  isDir: false,
                ),
                kind: FilePreviewKind.unsupported,
                source: null,
                loading: false,
                errorText: null,
                onOpenWithSystem: () {},
                onSaveAs: () {},
                onDownload: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in const ['取消', '外部应用打开', '另存为', '下载']) {
        expect(find.text(label), findsOneWidget);
      }
      final shortPreviewHeight = tester
          .getSize(find.byType(FilePreviewPane))
          .height;
      tester.view.physicalSize = const Size(360, 760);
      await tester.pumpAndSettle();
      final tallPreviewHeight = tester
          .getSize(find.byType(FilePreviewPane))
          .height;
      expect(tallPreviewHeight, greaterThan(shortPreviewHeight + 100));
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void _configureView(
  WidgetTester tester, {
  required Size size,
  FakeViewPadding padding = FakeViewPadding.zero,
  FakeViewPadding viewInsets = FakeViewPadding.zero,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  tester.view.viewInsets = viewInsets;
  addTearDown(tester.view.reset);
}

Future<void> _pumpHost(
  WidgetTester tester, {
  bool nested = false,
  ValueChanged<Object?>? onResult,
}) {
  return tester.pumpWidget(
    ShadApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              const Text('底层页面'),
              ShadButton(
                onPressed: () async {
                  final result = await showAppModal<Object?>(
                    context: context,
                    builder: (_) =>
                        nested ? const _NestedDialog() : const _TestDialog(),
                  );
                  onResult?.call(result);
                },
                child: const Text('打开'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NestedDialog extends StatelessWidget {
  const _NestedDialog();

  @override
  Widget build(BuildContext context) => const _TestDialog();
}

class _TestDialog extends StatelessWidget {
  const _TestDialog();

  @override
  Widget build(BuildContext context) {
    return const AppShadDialog(
      title: Text('Android 全屏'),
      backgroundColor: _surfaceColor,
      constraints: BoxConstraints(maxWidth: 240),
      closeIconData: LucideIcons.x,
      child: SizedBox(width: 180, height: 80, child: Text('模态内容')),
    );
  }
}

Finder _surfaceFinder() {
  return find.descendant(
    of: find.byType(AppShadDialog),
    matching: find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.color == _surfaceColor;
    }),
  );
}

class _FakeGateway extends Fake implements RemoteStorageGateway {}
