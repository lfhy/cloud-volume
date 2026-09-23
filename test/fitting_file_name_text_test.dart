// FittingFileNameText 的回归：像素感知快路径——名字放得下当前行宽就
// 原样显示（跨 18 字符门槛也放行），放不下才退到 compactDisplayName 的
// 字符预算截断；辅助技术始终拿到完整名。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/widgets/fitting_file_name_text.dart';

Widget _host(Widget child, {double? width}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: width == null ? child : SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);

  testWidgets('names beyond the character gate still render in full when '
      'they fit the width', (tester) async {
    // Ahem 等宽字体 14px/字符；300px 宽放得下 19 字符全名。
    await tester.pumpWidget(
      _host(
        const FittingFileNameText(
          name: 'default_blurred.png',
          style: style,
        ),
        width: 300,
      ),
    );
    expect(find.text('default_blurred.png'), findsOneWidget);
  });

  testWidgets('falls back to budget truncation when it does not fit', (
    tester,
  ) async {
    // 120px 只装得下 ~8 字符 → compactDisplayName(18) 截断。
    await tester.pumpWidget(
      _host(
        const FittingFileNameText(
          name: 'default_blurred.png',
          style: style,
        ),
        width: 120,
      ),
    );
    expect(find.text('default_blurred.png'), findsNothing);
    final elided = find.textContaining('...');
    expect(elided, findsOneWidget);
    expect(tester.widget<Text>(elided).data, endsWith('.png'));
  });

  testWidgets('measurement merges the ambient DefaultTextStyle', (
    tester,
  ) async {
    // 宿主题注入大字间距 → 合并后的测宽变宽 → 快路径不误放行。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 14,
                  letterSpacing: 20,
                ),
                child: const FittingFileNameText(
                  name: 'default_blurred.png',
                  style: style,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // 19 字符 × (14 + 20)px 远超 300px → 退到字符预算截断。
    expect(find.text('default_blurred.png'), findsNothing);
    expect(find.textContaining('...'), findsOneWidget);
  });
}
