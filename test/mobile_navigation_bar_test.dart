// 锁定移动底栏的主题化视觉契约:背景渐变随强调色派生(与桌面侧栏共享
// SidebarPalette),选中项复刻桌面侧栏胶囊(强调色前景/填充/描边 + w600),
// 未选中为 muted 前景,点击回调返回正确 value。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/theme/sidebar_palette.dart';
import 'package:remote_storage/widgets/mobile_navigation_bar.dart';

void main() {
  testWidgets('mobile bar follows accent theme and desktop selection visuals',
      (tester) async {
    const accent = Color(0xff1a56db);
    final palette = SidebarPalette.of(accent);
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
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

    // 背景渐变颜色来自 SidebarPalette(随强调色派生,遵循主题设置)。
    final boxDecorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(
      boxDecorations.any(
        (box) =>
            box.gradient is LinearGradient &&
            (box.gradient as LinearGradient).colors.first == palette.bgTop &&
            (box.gradient as LinearGradient).colors.last == palette.bgBottom,
      ),
      isTrue,
      reason: '底栏背景必须使用 SidebarPalette 的渐变(桌面侧栏同款)',
    );

    // 选中项:强调色前景 + w600;未选中项:muted 前景 + w400。
    final selectedText = tester.widget<Text>(find.text('账号'));
    expect(selectedText.style?.color, accent);
    expect(selectedText.style?.fontWeight, FontWeight.w600);
    final idleText = tester.widget<Text>(find.text('文件'));
    expect(idleText.style?.color, palette.muted);
    expect(idleText.style?.fontWeight, FontWeight.w400);

    // 选中胶囊:10% 填充 + 20% 描边(桌面侧栏同款)。
    final selectedContainer = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text('账号'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final selectedBox = selectedContainer.decoration! as BoxDecoration;
    expect(selectedBox.color, accent.withValues(alpha: 0.1));
    expect(selectedBox.border?.top.color, accent.withValues(alpha: 0.2));

    // 未选中胶囊:透明背景 + 同宽透明描边(切换时布局不跳动)。
    final idleContainer = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text('文件'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final idleBox = idleContainer.decoration! as BoxDecoration;
    expect(idleBox.color, Colors.transparent);
    expect(idleBox.border?.top.color, Colors.transparent);
    expect(idleBox.border?.top.width, selectedBox.border?.top.width);

    await tester.tap(find.text('文件'));
    expect(tapped, 0);
  });
}
