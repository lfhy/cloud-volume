// 主布局：侧边栏导航 + 右侧内容区。
// 侧边栏使用渐变背景 + 装饰圆形，风格与登录页左侧品牌面板统一。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/pages/cloud_storage_page.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/pages/global_trash_page.dart';
import 'package:remote_storage/pages/share_management_page.dart';
import 'package:remote_storage/pages/settings_page.dart';
import 'package:remote_storage/pages/transfers_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/widgets/app_brand_mark.dart';
import 'package:remote_storage/widgets/sidebar_transfer_status.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 侧边栏菜单项。
enum SidebarItem { fileManager, storage, trash, shares, transfers, settings }

class MainLayoutPage extends StatefulWidget {
  const MainLayoutPage({
    super.key,
    required this.state,
    required this.api,
    required this.selectedItem,
    required this.onSelectedItemChanged,
    required this.onEditConfig,
    required this.onRefresh,
  });

  final BootstrapState state;
  final RemoteStorageGateway api;
  final SidebarItem selectedItem;
  final ValueChanged<SidebarItem> onSelectedItemChanged;
  final VoidCallback onEditConfig;
  final VoidCallback onRefresh;

  @override
  State<MainLayoutPage> createState() => _MainLayoutPageState();
}

class _MainLayoutPageState extends State<MainLayoutPage> {
  bool get _sharesAvailable => widget.state.config.supportsShareLinks;

  SidebarItem get _effectiveSelectedItem {
    if (!_sharesAvailable && widget.selectedItem == SidebarItem.shares) {
      return SidebarItem.fileManager;
    }
    return widget.selectedItem;
  }

  @override
  void initState() {
    super.initState();
    TransferQueue.instance.bindApi(widget.api);
  }

  @override
  void didUpdateWidget(covariant MainLayoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      TransferQueue.instance.bindApi(widget.api);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final ac = ThemeController.of(context).accent.color;
    final bgTop = Color.lerp(const Color(0xffeef3ff), ac, 0.08)!;
    final bgBottom = Color.lerp(const Color(0xfff8faff), ac, 0.03)!;
    final muted = Color.lerp(const Color(0xff64748b), ac, 0.06)!;

    return Container(
      width: 236,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgTop, bgBottom],
        ),
      ),
      child: Stack(
        children: [
          // 装饰圆形。
          Positioned(
            top: -40,
            right: -30,
            child: _circle(140, ac.withValues(alpha: 0.06)),
          ),
          Positioned(
            bottom: 80,
            left: -40,
            child: _circle(120, ac.withValues(alpha: 0.04)),
          ),
          Positioned(
            top: 280,
            right: 20,
            child: _circle(50, ac.withValues(alpha: 0.03)),
          ),
          Positioned(
            bottom: 200,
            right: -20,
            child: _circle(80, ac.withValues(alpha: 0.06)),
          ),
          // 前景内容。
          Padding(
            padding: const EdgeInsets.only(top: 52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 品牌标识：图标 + 应用名。
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [const AppBrandMark(height: 42, width: 210)],
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
                // 菜单项。
                _navItem(
                  LucideIcons.folderOpen,
                  '文件管理',
                  SidebarItem.fileManager,
                  ac,
                  muted,
                ),
                _navItem(
                  LucideIcons.cloudCog,
                  '账号管理',
                  SidebarItem.storage,
                  ac,
                  muted,
                ),
                _navItem(
                  LucideIcons.trash2,
                  '回收站',
                  SidebarItem.trash,
                  ac,
                  muted,
                ),
                if (_sharesAvailable)
                  _navItem(
                    LucideIcons.share2,
                    '分享管理',
                    SidebarItem.shares,
                    ac,
                    muted,
                  ),
                _navItem(
                  LucideIcons.arrowLeftRight,
                  '任务队列',
                  SidebarItem.transfers,
                  ac,
                  muted,
                ),
                _navItem(
                  LucideIcons.settings2,
                  '系统设置',
                  SidebarItem.settings,
                  ac,
                  muted,
                ),
                const Spacer(),
                SidebarTransferStatus(
                  accent: ac,
                  muted: muted,
                  onTap: () =>
                      widget.onSelectedItemChanged(SidebarItem.transfers),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _navItem(
    IconData icon,
    String label,
    SidebarItem item,
    Color ac,
    Color muted,
  ) {
    final selected = _effectiveSelectedItem == item;
    final bg = selected ? ac.withValues(alpha: 0.1) : Colors.transparent;
    final fg = selected ? ac : muted;
    final border = selected
        ? Border.all(color: ac.withValues(alpha: 0.2))
        : Border.all(color: Colors.transparent);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: GestureDetector(
        onTap: () => widget.onSelectedItemChanged(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: border,
          ),
          child: Row(
            children: [
              Opacity(
                opacity: selected ? 1 : 0.9,
                child: Icon(icon, size: 17, color: fg),
              ),
              const SizedBox(width: 10),
              Text(
                label,
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
    );
  }

  Widget _buildContent() {
    final index = switch (widget.selectedItem) {
      SidebarItem.shares when !_sharesAvailable => 0,
      SidebarItem.fileManager => 0,
      SidebarItem.storage => 1,
      SidebarItem.trash => 2,
      SidebarItem.shares => 3,
      SidebarItem.transfers => 4,
      SidebarItem.settings => 5,
    };

    return IndexedStack(
      index: index,
      children: [
        FileManagerPage(
          api: widget.api,
          config: widget.state.config,
          profiles: widget.state.profiles,
          onEditConfig: widget.onEditConfig,
          onRefresh: widget.onRefresh,
        ),
        CloudStoragePage(
          state: widget.state,
          api: widget.api,
          onRefresh: widget.onRefresh,
        ),
        GlobalTrashPage(api: widget.api, config: widget.state.config),
        ShareManagementPage(api: widget.api, config: widget.state.config),
        TransfersPage(
          api: widget.api,
          config: widget.state.config,
          active: _effectiveSelectedItem == SidebarItem.transfers,
        ),
        SettingsPage(
          state: widget.state,
          api: widget.api,
          onEditConfig: widget.onEditConfig,
          onRefresh: widget.onRefresh,
        ),
      ],
    );
  }
}
