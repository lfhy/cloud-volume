// 桌面侧边栏的主题化视觉调色板:渐变背景、muted 前景与装饰圆形都从
// 当前强调色派生,使桌面导航遵循主题(强调色)设置。安卓底栏不复用此
// 调色板(定稿为纯主题背景 + 强调色选中,见 widgets/mobile_navigation_bar.dart)。

import 'package:flutter/material.dart';

/// 由强调色派生的桌面侧栏调色板。
class SidebarPalette {
  const SidebarPalette._({
    required this.accent,
    required this.bgTop,
    required this.bgBottom,
    required this.muted,
  });

  factory SidebarPalette.of(Color accent) => SidebarPalette._(
        accent: accent,
        bgTop: Color.lerp(const Color(0xffeef3ff), accent, 0.08)!,
        bgBottom: Color.lerp(const Color(0xfff8faff), accent, 0.03)!,
        muted: Color.lerp(const Color(0xff64748b), accent, 0.06)!,
      );

  /// 当前强调色。
  final Color accent;

  /// 渐变背景上端基色。
  final Color bgTop;

  /// 渐变背景下端基色。
  final Color bgBottom;

  /// 未选中项前景(muted 灰与强调色的弱混)。
  final Color muted;

  /// 侧栏/底栏背景渐变。
  LinearGradient get background => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bgTop, bgBottom],
      );

  /// 背景装饰圆形(由使用方的 Stack 默认裁剪在栏内)。
  Widget decorCircle(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: alpha),
        ),
      );
}
