// 移动端专属设置节:自定义底部导航栏的显示项与顺序。
// 仅 Android 渲染(由 settings 页的 tab 分发控制);每次变更即时保存到
// MobileNavPreferences 并通知 main_layout 重建底栏。视觉遵循设置卡规范:
// 顶部 12px muted 简介 + secondary 容器,不用 textTheme.h4。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/sidebar_item.dart';
import 'package:remote_storage/state/mobile_nav_preferences.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingsMobileNavSection extends StatefulWidget {
  const SettingsMobileNavSection({super.key, required this.theme});

  final ShadThemeData theme;

  @override
  State<SettingsMobileNavSection> createState() =>
      _SettingsMobileNavSectionState();
}

class _SettingsMobileNavSectionState extends State<SettingsMobileNavSection> {
  List<SidebarItem> _selected = List.from(MobileNavPreferences.instance.items);

  @override
  void initState() {
    super.initState();
    // 监听偏好变化:异步 load 完成或外部变更时同步本地副本,避免用
    // 默认派生配置覆盖用户存储。
    MobileNavPreferences.instance.addListener(_syncFromPreferences);
  }

  @override
  void dispose() {
    MobileNavPreferences.instance.removeListener(_syncFromPreferences);
    super.dispose();
  }

  void _syncFromPreferences() {
    if (!mounted) return;
    setState(() => _selected = List.from(MobileNavPreferences.instance.items));
  }

  bool _isSelected(SidebarItem item) => _selected.contains(item);

  /// 应用变更:先本地校验约束(2–5 项、首页/设置至少保留一个、最多 5 项),
  /// 通过后立即持久化;失败则提示且不动状态。
  Future<void> _apply(List<SidebarItem> next) async {
    try {
      await MobileNavPreferences.instance.save(next);
    } on ArgumentError catch (error) {
      if (mounted) showAppToast(context, message: error.message.toString());
    }
  }

  void _toggle(SidebarItem item, bool enabled) {
    final next = List<SidebarItem>.from(_selected);
    if (enabled) {
      next.add(item);
    } else {
      next.remove(item);
    }
    _apply(next);
  }

  void _move(SidebarItem item, int offset) {
    final index = _selected.indexOf(item);
    if (index < 0) return;
    final target = index + offset;
    if (target < 0 || target >= _selected.length) return;
    final next = List<SidebarItem>.from(_selected);
    final moved = next.removeAt(index);
    next.insert(target, moved);
    _apply(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '自定义底部导航栏显示的页面与顺序(2–5 项;「首页」与「设置」至少保留一个)。更改立即生效。',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              // 已显示项:按当前顺序,可上下移动、可移除。
              for (var i = 0; i < _selected.length; i++)
                _navRow(
                  _selected[i],
                  enabled: true,
                  onMoveUp: i > 0 ? () => _move(_selected[i], -1) : null,
                  onMoveDown: i < _selected.length - 1
                      ? () => _move(_selected[i], 1)
                      : null,
                ),
              if (_selected.length < kMobileBottomBarPool.length) ...[
                Divider(
                  height: 24,
                  color: theme.colorScheme.border.withValues(alpha: 0.5),
                ),
                // 未显示项:开启即追加到末尾。
                for (final item
                    in kMobileBottomBarPool.where((i) => !_isSelected(i)))
                  _navRow(item, enabled: false),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => _apply(List.from(kMobileBottomBarDefault)),
                  child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _navRow(
    SidebarItem item, {
    required bool enabled,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
  }) {
    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(item.icon, size: 16, color: theme.colorScheme.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.desktopLabel,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (enabled) ...[
            _moveButton(LucideIcons.chevronUp, '上移', onMoveUp),
            _moveButton(LucideIcons.chevronDown, '下移', onMoveDown),
          ],
          const SizedBox(width: 4),
          ShadSwitch(
            value: enabled,
            onChanged: (value) => _toggle(item, value),
          ),
        ],
      ),
    );
  }

  Widget _moveButton(IconData icon, String tooltip, VoidCallback? onPressed) {
    final theme = widget.theme;
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 16,
        color: onPressed == null
            ? theme.colorScheme.mutedForeground.withValues(alpha: 0.4)
            : theme.colorScheme.mutedForeground,
      ),
    );
  }
}
