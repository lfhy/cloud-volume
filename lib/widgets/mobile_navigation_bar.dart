// 安卓底部导航栏:无底色装饰(与应用主题背景色融合),选中项仅图标与
// 文字变为主题强调色(w600),未选中为 mutedForeground——按用户定稿的
// 参考设计实现,无胶囊/描边/指示器。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

/// 移动底栏:背景为应用主题背景色,遵循主题设置;选中态只有颜色变化
/// (强调色 + w600)。参考设计无选中底块;顶部分割线系用户反馈后补充。
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

  /// 主题强调色(`ThemeController` 的 accent),选中项图标与文字的颜色。
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    // 背景铺满到屏幕物理底部(SafeArea 只内缩内容),无渐变;顶部一条
    // 全量主题 border 线提供与内容区的分割感——强度对齐参考设计
    // (白底约 8% 黑;全量 border 略强于参考的 7.8%,同档不明显)。
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(
          top: BorderSide(color: theme.colorScheme.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final selected = items[i].value == selectedValue;
                      return _MobileNavItem(
                        item: items[i],
                        selected: selected,
                        foreground:
                            selected ? accent : theme.colorScheme.mutedForeground,
                        onTap: () => onSelected(items[i].value),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 底栏单项:图标上、文字下,颜色由父级给定(选中 = 强调色,未选中 =
/// mutedForeground);选中仅提升字重,不加任何背景装饰。
class _MobileNavItem<T> extends StatelessWidget {
  const _MobileNavItem({
    required this.item,
    required this.selected,
    required this.foreground,
    required this.onTap,
  });

  final MobileNavItem<T> item;
  final bool selected;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // label 由内部 Text 自报,避免 TalkBack 连读两遍。
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 命中区域至少 48dp(图标 24 + 间距 4 + 文字约 14 原生高度不足)。
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 24, color: foreground),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
