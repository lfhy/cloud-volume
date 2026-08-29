// 主布局：侧边栏导航 + 右侧内容区。
// 侧边栏使用渐变背景 + 装饰圆形，风格与登录页左侧品牌面板统一。

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/pages/cloud_storage_page.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/models/sync_remote_open_request.dart';
import 'package:remote_storage/pages/file_sync_tasks_page.dart';
import 'package:remote_storage/services/sync_directory_navigation.dart';
import 'package:remote_storage/pages/global_trash_page.dart';
import 'package:remote_storage/pages/share_management_page.dart';
import 'package:remote_storage/pages/settings_page.dart';
import 'package:remote_storage/pages/transfers_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/theme/sidebar_palette.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/widgets/app_brand_mark.dart';
import 'package:remote_storage/widgets/mobile_navigation_bar.dart';
import 'package:remote_storage/widgets/sidebar_transfer_status.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 侧边栏菜单项。
enum SidebarItem { fileManager, storage, trash, shares, transfers, fileSyncTasks, settings }

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
  SyncRemoteOpenRequest? _pendingSyncRemoteOpen;

  void _onOpenSyncRemoteFromSyncPage(SyncRemoteOpenRequest request) {
    setState(() => _pendingSyncRemoteOpen = request);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onSelectedItemChanged(SidebarItem.fileManager);
    });
  }

  void _clearPendingSyncRemoteOpen() {
    if (_pendingSyncRemoteOpen == null) return;
    setState(() => _pendingSyncRemoteOpen = null);
  }

 bool get _sharesAvailable => widget.state.config.supportsShareLinks;
  // Sync requires local filesystem access and desktop-only FFI services.
  bool get _syncAvailable =>
      !isWebPlatform &&
      defaultTargetPlatform != TargetPlatform.android;

  SidebarItem get _effectiveSelectedItem {
    if (!_sharesAvailable && widget.selectedItem == SidebarItem.shares) {
      return SidebarItem.fileManager;
    }
    return widget.selectedItem;
  }

  @override
  void initState() {
    super.initState();
    SyncDirectoryNavigation.instance.setHandler(_onOpenSyncRemoteFromSyncPage);
    TransferQueue.instance.bindApi(widget.api);
    SyncProfileNotifier.instance.bindApi(widget.api);
  }

  @override
  void dispose() {
    SyncDirectoryNavigation.instance.setHandler(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainLayoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      TransferQueue.instance.bindApi(widget.api);
      SyncProfileNotifier.instance.bindApi(widget.api);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
      body: isAndroid
          ? _buildContent()
          : Row(
              children: [
                _buildSidebar(),
                Expanded(child: _buildContent()),
              ],
            ),
      bottomNavigationBar: isAndroid ? _buildMobileNavigation() : null,
    );
  }

  // Mobile navigation replaces the desktop rail without duplicating pages; it
  // uses the theme background with accent-colored selection (see
  // MobileNavigationBar for the finalized visual contract).
  Widget _buildMobileNavigation() {
    return MobileNavigationBar<SidebarItem>(
      accent: ThemeController.of(context).accent.color,
      selectedValue: _effectiveSelectedItem,
      onSelected: widget.onSelectedItemChanged,
      items: const [
        MobileNavItem(
          value: SidebarItem.fileManager,
          icon: LucideIcons.folderOpen,
          label: '文件',
        ),
        MobileNavItem(
          value: SidebarItem.storage,
          icon: LucideIcons.cloudCog,
          label: '账号',
        ),
        MobileNavItem(
          value: SidebarItem.trash,
          icon: LucideIcons.trash2,
          label: '回收站',
        ),
        MobileNavItem(
          value: SidebarItem.transfers,
          icon: LucideIcons.arrowLeftRight,
          label: '任务',
        ),
        MobileNavItem(
          value: SidebarItem.settings,
          icon: LucideIcons.settings2,
          label: '设置',
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    final palette =
        SidebarPalette.of(ThemeController.of(context).accent.color);
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
          Positioned(
            top: 280,
            right: 20,
            child: palette.decorCircle(50, 0.03),
          ),
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
                if (_syncAvailable)
                  _navItem(
                    LucideIcons.refreshCw,
                    '文件同步',
                    SidebarItem.fileSyncTasks,
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

  Widget _navItem(
    IconData icon,
    String label,
    SidebarItem item,
    Color ac,
    Color muted,
  ) {
    return _SidebarNavItem(
      icon: icon,
      label: label,
      selected: _effectiveSelectedItem == item,
      accent: ac,
      muted: muted,
      onTap: () => widget.onSelectedItemChanged(item),
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
      SidebarItem.fileSyncTasks => 5,
      SidebarItem.settings => 6,
    };

    return IndexedStack(
      index: index,
      children: [
        FileManagerPage(
          api: widget.api,
          config: widget.state.config,
          profiles: widget.state.profiles,
          onRefresh: widget.onRefresh,
          pendingSyncRemoteOpen: _pendingSyncRemoteOpen,
          onPendingSyncRemoteOpenConsumed: _clearPendingSyncRemoteOpen,
          onOpenAccountManagement: () =>
              widget.onSelectedItemChanged(SidebarItem.storage),
        ),
        CloudStoragePage(
          state: widget.state,
          api: widget.api,
          onRefresh: widget.onRefresh,
        ),
        GlobalTrashPage(
          api: widget.api,
          config: widget.state.config,
          profiles: widget.state.profiles,
        ),
        ShareManagementPage(api: widget.api, config: widget.state.config),
        TransfersPage(
          api: widget.api,
          config: widget.state.config,
          active: _effectiveSelectedItem == SidebarItem.transfers,
        ),
        FileSyncTasksPage(
          api: widget.api,
          config: widget.state.config,
          profiles: widget.state.profiles,
          active: _effectiveSelectedItem == SidebarItem.fileSyncTasks,
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

/// 侧边栏单项：未选中时鼠标悬停有浅色背景反馈。
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
        cursor: _hovered
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected
                  ? baseBg
                  : Color.alphaBlend(hoverOverlay, baseBg),
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
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
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
