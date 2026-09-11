// Android 顶层页共享 chrome 的回归测试：MobilePageHeader 的标题/副标题/
// 单一动作入口契约，动作抽屉的 48dp 行高，以及设置页系统 Back 钩子的
// consume 语义。这些测试点对应 TODO「其他 Android 页面小屏布局优化」。


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/state/mobile_settings_navigation.dart';
import 'package:remote_storage/widgets/mobile_page_chrome.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _host(Widget child) {
  return ShadApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('header renders title and subtitle without an action entry', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        _host(const MobilePageHeader(title: '设置', subtitle: '管理应用与连接偏好。')),
      );
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('管理应用与连接偏好。'), findsOneWidget);
      // 无动作时不渲染入口按钮。
      expect(find.bySemanticsLabel('新增账号'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('action entry is 48dp, semantically labeled, opens the sheet', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var triggered = false;
      await tester.pumpWidget(
        _host(
          MobilePageHeader(
            title: '账号管理',
            subtitle: '新增与管理云存储账号。',
            actionSheetTitle: '账号操作',
            actionsSemanticLabel: '新增账号',
            actions: [
              MobilePageAction(
                label: '新增账号',
                icon: LucideIcons.plus,
                onPressed: () => triggered = true,
              ),
            ],
          ),
        ),
      );

      final entry = find.bySemanticsLabel('新增账号');
      expect(entry, findsOneWidget);
      final size = tester.getSize(entry);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(entry);
      await tester.pumpAndSettle();
      // 抽屉标题与动作行出现，且动作弹层真实挂载。
      expect(find.text('账号操作'), findsOneWidget);
      expect(find.byType(AppShadDialog), findsOneWidget);

      await tester.tap(find.text('新增账号').last);
      await tester.pumpAndSettle();
      expect(triggered, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('MobileSettingsNavigation consumes back only while bound', (
    tester,
  ) async {
    final navigation = MobileSettingsNavigation();
    var collapsed = 0;
    expect(navigation.consumeBack(), isFalse);
    navigation.bind(() => collapsed++);
    expect(navigation.consumeBack(), isTrue);
    expect(collapsed, 1);
    // clear 后（回到设置索引）不再吞 Back。
    navigation.clear();
    expect(navigation.consumeBack(), isFalse);
    expect(collapsed, 1);
    navigation.dispose();
  });
}
