// 导航项枚举:桌面侧栏与移动底栏/首页共用的单一事实来源。
// 桌面侧栏显示除 [SidebarItem.home] 外的全部项;移动端由用户在设置里
// 自定义底栏可见项与顺序(见 state/mobile_nav_preferences.dart)。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 侧边栏/底栏菜单项。
enum SidebarItem {
  fileManager,
  storage,
  trash,
  shares,
  transfers,
  fileSyncTasks,
  settings,
  /// 移动端首页(概览 + 快捷入口 + 最近任务);桌面侧栏不显示。
  home,
}

/// 导航项的图标与文案。
extension SidebarItemInfo on SidebarItem {
  IconData get icon => switch (this) {
        SidebarItem.fileManager => LucideIcons.folderOpen,
        SidebarItem.storage => LucideIcons.cloudCog,
        SidebarItem.trash => LucideIcons.trash2,
        SidebarItem.shares => LucideIcons.share2,
        SidebarItem.transfers => LucideIcons.arrowLeftRight,
        SidebarItem.fileSyncTasks => LucideIcons.refreshCw,
        SidebarItem.settings => LucideIcons.settings2,
        SidebarItem.home => LucideIcons.house,
      };

  /// 桌面侧栏文案。
  String get desktopLabel => switch (this) {
        SidebarItem.fileManager => '文件管理',
        SidebarItem.storage => '账号管理',
        SidebarItem.trash => '回收站',
        SidebarItem.shares => '分享管理',
        SidebarItem.transfers => '任务队列',
        SidebarItem.fileSyncTasks => '文件同步',
        SidebarItem.settings => '系统设置',
        SidebarItem.home => '首页',
      };

  /// 移动端底栏文案(窄屏短标签);首页快捷入口用 [desktopLabel]
  /// (2×2 卡片宽度充足)。
  String get mobileLabel => switch (this) {
        SidebarItem.fileManager => '文件',
        SidebarItem.storage => '账号',
        SidebarItem.trash => '回收站',
        SidebarItem.shares => '分享',
        SidebarItem.transfers => '任务',
        SidebarItem.fileSyncTasks => '同步',
        SidebarItem.settings => '设置',
        SidebarItem.home => '首页',
      };
}
