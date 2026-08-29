// 桌面侧栏与安卓底栏共享的主题化视觉调色板:渐变背景、muted 前景与
// 装饰圆形都从当前强调色派生,两端导航遵循同一套主题(强调色)设置。

import 'package:flutter/material.dart';

/// 由强调色派生的导航栏调色板(桌面侧栏 / 安卓底栏共用)。
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
