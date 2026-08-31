// 桌面端侧边栏:品牌标识 + 渐变背景(SidebarPalette,随强调色主题)+ 装饰
// 圆形 + 导航项列表(hover 正典见 docs/features/ui_rules.md)。
// 从 main_layout_page.dart 拆出以保持主装配文件在 500 行内。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/sidebar_item.dart';
import 'package:remote_storage/theme/sidebar_palette.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/widgets/app_brand_mark.dart';
import 'package:remote_storage/widgets/sidebar_transfer_status.dart';

/// 桌面侧栏。[sharesAvailable]/[syncAvailable] 控制桌面专属入口的显隐。
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.selectedItem,
    required this.sharesAvailable,
    required this.syncAvailable,
    required this.onSelected,
  });

  final SidebarItem selectedItem;
  final bool sharesAvailable;
  final bool syncAvailable;
  final ValueChanged<SidebarItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(ThemeController.of(context).accent.color);
    final ac = palette.accent;
    final muted = palette.muted;

    return Container(
      width: 236,
      decoration: BoxDecoration(gradient: palette.background),
      child: Stack(
        children: [
          // 装饰圆形。
          Positioned(
            top: -40,
            right: -30,
            child: palette.decorCircle(140, 0.06),
          ),
          Positioned(
            bottom: 80,
            left: -40,
            child: palette.decorCircle(120, 0.04),
          ),
          Positioned(top: 280, right: 20, child: palette.decorCircle(50, 0.03)),
          Positioned(
            bottom: 200,
            right: -20,
            child: palette.decorCircle(80, 0.06),
          ),
          // 前景内容。
          Padding(
            padding: const EdgeInsets.only(top: 52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 品牌标识:图标 + 应用名。
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [AppBrandMark(height: 42, width: 210)],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ac.withValues(alpha: 0.2),
                          ac.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // 菜单项:桌面侧栏和移动端底栏共享同一组页面标识。
                for (final entry in _desktopEntries)
                  if (entry != SidebarItem.shares || sharesAvailable)
                    if (entry != SidebarItem.fileSyncTasks || syncAvailable)
                      _SidebarNavItem(
                        icon: entry.icon,
                        label: entry.desktopLabel,
                        selected: selectedItem == entry,
                        accent: ac,
                        muted: muted,
                        onTap: () => onSelected(entry),
                      ),
                const Spacer(),
                SidebarTransferStatus(
                  accent: ac,
                  muted: muted,
                  onTap: () => onSelected(SidebarItem.transfers),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const List<SidebarItem> _desktopEntries = [
    SidebarItem.fileManager,
    SidebarItem.storage,
    SidebarItem.trash,
    SidebarItem.shares,
    SidebarItem.transfers,
    SidebarItem.fileSyncTasks,
    SidebarItem.settings,
  ];
}

/// 侧边栏单项:未选中时鼠标悬停有浅色背景反馈(hover 正典)。
class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.muted,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final Color muted;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final ac = widget.accent;
    final fg = selected
        ? ac
        : _hovered
        ? ac.withValues(alpha: 0.9)
        : widget.muted;
    final baseBg = selected ? ac.withValues(alpha: 0.1) : Colors.transparent;
    final hoverOverlay = selected
        ? Colors.transparent
        : ac.withValues(alpha: _hovered ? 0.1 : 0);
    final border = selected
        ? Border.all(color: ac.withValues(alpha: 0.2))
        : Border.all(color: Colors.transparent);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        // Use basic arrow when idle so the cursor doesn't get stuck on a
        // pointing hand inherited from an ancestor.
        cursor: _hovered ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected ? baseBg : Color.alphaBlend(hoverOverlay, baseBg),
              borderRadius: BorderRadius.circular(8),
              border: border,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(widget.icon, size: 17, color: fg),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
