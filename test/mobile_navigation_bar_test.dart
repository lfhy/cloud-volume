// 锁定移动底栏的定稿视觉契约:背景为应用主题背景色(无渐变/胶囊/装饰),
// 选中项仅图标与文字变为主题强调色(w600),未选中为 mutedForeground
// (w500),点击回调返回正确 value。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/widgets/mobile_navigation_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('mobile bar uses theme background and accent-only selection',
      (tester) async {
    const accent = Color(0xff1a56db);
    int? tapped;
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          bottomNavigationBar: MobileNavigationBar<int>(
            accent: accent,
            selectedValue: 1,
            onSelected: (value) => tapped = value,
            items: const [
              MobileNavItem(value: 0, icon: Icons.folder, label: '文件'),
              MobileNavItem(value: 1, icon: Icons.cloud, label: '账号'),
            ],
          ),
        ),
      ),
    );

    // 定稿设计无任何渐变/胶囊装饰:全部 BoxDecoration 都不得带渐变。
    final boxDecorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(
      boxDecorations.any((box) => box.gradient != null),
      isFalse,
      reason: '底栏背景必须是纯主题背景色,不得有渐变',
    );

    // 顶部有一条主题 border 细线提供与内容区的分割感。
    final theme = ShadTheme.of(
      tester.element(find.byType(MobileNavigationBar<int>)),
    );
    expect(
      boxDecorations.any(
        (box) =>
            box.border?.top.color ==
            theme.colorScheme.border.withValues(alpha: 0.7),
      ),
      isTrue,
      reason: '底栏顶部必须有主题色分割线',
    );

    // 选中项:图标与文字都用主题强调色,文字 w600。
    final selectedText = tester.widget<Text>(find.text('账号'));
    expect(selectedText.style?.color, accent);
    expect(selectedText.style?.fontWeight, FontWeight.w600);
    expect(tester.widget<Icon>(find.byIcon(Icons.cloud)).color, accent);

    // 未选中项:mutedForeground + w500。
    final idleText = tester.widget<Text>(find.text('文件'));
    expect(idleText.style?.color, theme.colorScheme.mutedForeground);
    expect(idleText.style?.fontWeight, FontWeight.w500);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.folder)).color,
      theme.colorScheme.mutedForeground,
    );

    await tester.tap(find.text('文件'));
    expect(tapped, 0);
  });
}
