// 移动端底栏自定义配置:哪些导航项显示、按什么顺序。持久化到
// SharedPreferences(与 update_settings 同模式),损坏/非法数据回退默认。
// 设置页的「底部导航」节(仅 Android)读写此配置,main_layout 监听变化
// 重建底栏。

import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/sidebar_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key:JSON 数组字符串(枚举名,顺序即显示顺序)。
const String kMobileBottomBarKey = 'mobile.bottom_bar_items';
const String _legacyHomeItemName = 'home';

/// 底栏可选池(固定展示顺序,设置 UI 与校验共用)。移动端文件页就是
/// 首屏,不再提供独立的 home tab;旧数据中的 home 会迁移为 settings。
const List<SidebarItem> kMobileBottomBarPool = [
  SidebarItem.fileManager,
  SidebarItem.storage,
  SidebarItem.transfers,
  SidebarItem.trash,
  SidebarItem.settings,
];

/// 默认底栏:文件 · 账号 · 任务 · 回收站 · 设置。
const List<SidebarItem> kMobileBottomBarDefault = [
  SidebarItem.fileManager,
  SidebarItem.storage,
  SidebarItem.transfers,
  SidebarItem.trash,
  SidebarItem.settings,
];

/// 底栏配置单例:懒加载 + 变更通知。
class MobileNavPreferences extends ChangeNotifier {
  MobileNavPreferences._();

  static final MobileNavPreferences instance = MobileNavPreferences._();

  List<SidebarItem> _items = List<SidebarItem>.from(kMobileBottomBarDefault);
  bool _loaded = false;

  /// 当前底栏项(顺序即显示顺序)。
  List<SidebarItem> get items => List<SidebarItem>.unmodifiable(_items);

  /// 首帧前未加载完成时按默认渲染;load 完成后如有差异会通知重建。
  bool get loaded => _loaded;

  /// 幂等加载;解析失败或约束不满足时回退默认。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _items = _decode(prefs.getString(kMobileBottomBarKey));
    notifyListeners();
  }

  /// 保存新配置;非法输入抛 [ArgumentError](调用方 UI 已做约束)。
  Future<void> save(List<SidebarItem> items) async {
    final validated = _validate(items);
    _items = validated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kMobileBottomBarKey, _encode(validated));
    notifyListeners();
  }

  /// 恢复默认并持久化。
  Future<void> resetToDefault() => save(kMobileBottomBarDefault);

  static String _encode(List<SidebarItem> items) =>
      '[${items.map((e) => '"${e.name}"').join(',')}]';

  static List<SidebarItem> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return List.from(kMobileBottomBarDefault);
    // 容错解析:逐个名字映射,忽略未知/重复项;旧 home 项迁移为 settings。
    final names = raw.replaceAll('[', '').replaceAll(']', '').split(',');
    final parsed = <SidebarItem>[];
    for (final name in names) {
      final cleaned = name.trim().replaceAll('"', '');
      if (cleaned.isEmpty) continue;
      if (cleaned == _legacyHomeItemName) {
        if (!parsed.contains(SidebarItem.settings)) {
          parsed.add(SidebarItem.settings);
        }
        continue;
      }
      for (final item in SidebarItem.values) {
        if (kMobileBottomBarPool.contains(item) &&
            item.name == cleaned &&
            !parsed.contains(item)) {
          parsed.add(item);
        }
      }
    }
    return _satisfiesConstraints(parsed)
        ? parsed
        : List.from(kMobileBottomBarDefault);
  }

  /// 校验并归一:仅保留池内项、去重;项数超限显式报错(不静默截断,
  /// 设置 UI 需向用户提示而非默默丢弃操作)。
  static List<SidebarItem> _validate(List<SidebarItem> items) {
    if (items.length > 5) {
      throw ArgumentError('底部导航最多显示 5 项');
    }
    final normalized = <SidebarItem>[];
    for (final item in items) {
      if (kMobileBottomBarPool.contains(item) && !normalized.contains(item)) {
        normalized.add(item);
      }
    }
    if (!_satisfiesConstraints(normalized)) {
      throw ArgumentError('底部导航至少保留 2 项,且必须保留「设置」');
    }
    return normalized;
  }

  /// 约束:2–5 项;设置必须保留,保证底栏配置仍可恢复。
  static bool _satisfiesConstraints(List<SidebarItem> items) {
    if (items.length < 2 || items.length > 5) return false;
    if (!kMobileBottomBarPool.toSet().containsAll(items)) return false;
    return items.contains(SidebarItem.settings);
  }

  /// 测试用途。
  @visibleForTesting
  void resetForTest() {
    _items = List.from(kMobileBottomBarDefault);
    _loaded = false;
  }
}
