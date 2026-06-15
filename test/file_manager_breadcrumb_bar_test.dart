// File manager breadcrumb tests cover responsive path collapsing behavior.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/widgets/file_manager_breadcrumb_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('does not truncate a visible parent crumb', (tester) async {
    tester.view.physicalSize = const Size(760, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final theme = ShadTheme.of(context);
              return SizedBox(
                width: 620,
                child: FileManagerBreadcrumbBar(
                  theme: theme,
                  activeBucket: '百度云资源',
                  breadcrumbs: const <String>['百度云解压'],
                  onOpenBucketList: () {},
                  onOpenBucketRoot: () {},
                  onOpenCrumb: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('百度云资源'), findsOneWidget);
    expect(find.text('百度云解压'), findsOneWidget);
    expect(
      tester.getSize(find.text('百度云资源')).width,
      greaterThanOrEqualTo(_textWidth('百度云资源')),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps recent ancestor directories at their natural width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var openedBucketList = 0;
    var openedBucketRoot = 0;
    var openedCrumb = -2;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final theme = ShadTheme.of(context);
              return SizedBox(
                width: 820,
                child: FileManagerBreadcrumbBar(
                  theme: theme,
                  activeBucket: '百度网盘账号-with-very-long-profile-name',
                  breadcrumbs: const <String>[
                    'AI',
                    'AI-image-generation-projects',
                    'novelai-webui一键包',
                  ],
                  onOpenBucketList: () => openedBucketList++,
                  onOpenBucketRoot: () => openedBucketRoot++,
                  onOpenCrumb: (index) => openedCrumb = index,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('百度网盘账号-with-very-long-profile-name'), findsNothing);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('AI-image-generation-projects'), findsOneWidget);
    expect(find.text('novelai-webui一键包'), findsOneWidget);
    expect(
      tester.getSize(find.text('AI-image-generation-projects')).width,
      greaterThan(220),
    );

    await tester.tap(find.text('AI'));
    await tester.pump();

    expect(openedBucketList, 0);
    expect(openedBucketRoot, 0);
    expect(openedCrumb, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

double _textWidth(String text) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}
