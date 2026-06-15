// 左侧品牌面板：明亮渐变背景，展示品牌标识、标语和主题色选择器。
// 所有装饰颜色基于当前主题色动态生成。

import 'package:flutter/material.dart';
import 'package:remote_storage/app/app_brand.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/widgets/app_brand_mark.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';

class ConfigLeftPanel extends StatelessWidget {
  const ConfigLeftPanel({super.key, required this.configPath});

  final String configPath;

  @override
  Widget build(BuildContext context) {
    final accent = ThemeController.of(context).accent;
    final ac = accent.color;

    // 明亮渐变背景。
    final bgTop = Color.lerp(const Color(0xffeef3ff), ac, 0.08)!;
    final bgBottom = Color.lerp(const Color(0xfff8faff), ac, 0.03)!;

    // 装饰元素。
    final circleLight = ac.withValues(alpha: 0.06);

    // 文字颜色。
    final heading = Color.lerp(const Color(0xff1e293b), ac, 0.15)!;
    final muted = Color.lerp(const Color(0xff64748b), ac, 0.06)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgTop, bgBottom],
        ),
      ),
      child: Stack(
        children: [
          // 装饰性圆形，增加层次感。
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: circleLight,
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: -50,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: circleLight,
              ),
            ),
          ),
          Positioned(
            top: 160,
            left: 80,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ac.withValues(alpha: 0.04),
              ),
            ),
          ),
          // 主内容区。
          Padding(
            padding: const EdgeInsets.only(
              left: 40,
              right: 40,
              top: 56,
              bottom: 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 品牌标识。
                const AppBrandMark(height: 50, width: 230),
                const SizedBox(height: 6),
                const Spacer(flex: 3),
                // 标语。
                Text(
                  appBrandTagline,
                  style: TextStyle(
                    color: heading,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: 16),
                // 装饰横线。
                Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(
                    color: ac.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  appBrandDescription,
                  style: TextStyle(color: muted, fontSize: 13, height: 1.7),
                ),
                const Spacer(flex: 4),
                // 主题色选择器。
                _AccentPicker(muted: muted),
                const SizedBox(height: 24),
                // 底部安全提示。
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 12, color: muted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '凭证仅保存在本地',
                        style: TextStyle(color: muted, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 主题色选择器。
class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.muted});

  final Color muted;

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '主题色',
          style: TextStyle(
            color: muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final preset in AccentPreset.values)
              _AccentDot(
                preset: preset,
                isSelected: controller.accent == preset,
                onTap: () => controller.onAccentChanged(preset),
              ),
          ],
        ),
      ],
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final AccentPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AppTooltip(
        message: preset.label,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: preset.color,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(
                    color: Color.lerp(preset.color, Colors.white, 0.3)!,
                    width: 2.5,
                  )
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 1,
                  ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: preset.color.withValues(alpha: 0.35),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
