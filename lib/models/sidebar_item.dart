// 导航项枚举:桌面侧栏与移动底栏共用的单一事实来源。移动端由用户在
// 设置里自定义底栏可见项与顺序(见 state/mobile_nav_preferences.dart)。

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
  };

  /// 移动端底栏文案(窄屏短标签)。
  String get mobileLabel => switch (this) {
    SidebarItem.fileManager => '文件',
    SidebarItem.storage => '账号',
    SidebarItem.trash => '回收站',
    SidebarItem.shares => '分享',
    SidebarItem.transfers => '任务',
    SidebarItem.fileSyncTasks => '同步',
    SidebarItem.settings => '设置',
  };
}
