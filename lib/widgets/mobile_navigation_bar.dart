// 安卓底部导航栏:复用桌面侧栏的主题化渐变背景与选中胶囊视觉,
// 取代 Material NavigationBar,使移动端导航遵循应用的主题(强调色)设置。

import 'package:flutter/material.dart';
import 'package:remote_storage/theme/sidebar_palette.dart';

/// 底栏单个目的地的描述。
class MobileNavItem<T> {
  const MobileNavItem({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;
  final String label;
}

/// 主题化移动底栏:背景渐变、装饰圆形与选中态均与桌面侧栏
/// (`main_layout_page.dart` 的 `_SidebarNavItem`)保持一致。
class MobileNavigationBar<T> extends StatelessWidget {
  const MobileNavigationBar({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    required this.accent,
  });

  final List<MobileNavItem<T>> items;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(accent);
    // 渐变在最外层铺满到屏幕物理底部(SafeArea 只内缩内容),系统导航条
    // 区域不会露出 Scaffold 背景形成色带。
    return Container(
      decoration: BoxDecoration(gradient: palette.background),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            // 与桌面侧栏同款的装饰圆形(Stack 默认 hardEdge 裁剪在栏内)。
            Positioned(
              top: -40,
              right: -30,
              child: palette.decorCircle(140, 0.06),
            ),
            Positioned(
              bottom: -30,
              left: -40,
              child: palette.decorCircle(120, 0.04),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: _MobileNavItem(
                        item: items[i],
                        selected: items[i].value == selectedValue,
                        palette: palette,
                        onTap: () => onSelected(items[i].value),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏单项:选中视觉复刻桌面侧栏——强调色前景 + 10% 填充 + 20% 描边
/// 胶囊;未选中为 muted 前景、透明背景(保留同宽描边避免布局跳动)。
class _MobileNavItem<T> extends StatelessWidget {
  const _MobileNavItem({
    required this.item,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final MobileNavItem<T> item;
  final bool selected;
  final SidebarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = palette.accent;
    final fg = selected ? ac : palette.muted;
    // label 由内部 Text 自报,避免 TalkBack 连读两遍。
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? ac.withValues(alpha: 0.1) : Colors.transparent,
            // 圆角与桌面 _SidebarNavItem 一致(8)。
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? ac.withValues(alpha: 0.2) : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 21, color: fg),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
