// 主布局:桌面侧栏(DesktopSidebar)/移动底栏(MobileNavigationBar,用户
// 可在设置里自定义显示项与顺序)+ 右侧内容区(IndexedStack)。移动端由
// PopScope + TabNavHistory 提供系统返回键回退上一个页面。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/sidebar_item.dart';
import 'package:remote_storage/models/sync_remote_open_request.dart';
import 'package:remote_storage/pages/cloud_storage_page.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/pages/file_sync_tasks_page.dart';
import 'package:remote_storage/pages/global_trash_page.dart';
import 'package:remote_storage/pages/mobile_home_page.dart';
import 'package:remote_storage/pages/settings_page.dart';
import 'package:remote_storage/pages/share_management_page.dart';
import 'package:remote_storage/pages/transfers_page.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/services/sync_directory_navigation.dart';
import 'package:remote_storage/state/mobile_nav_preferences.dart';
import 'package:remote_storage/state/tab_nav_history.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/widgets/desktop_sidebar.dart';
import 'package:remote_storage/widgets/mobile_navigation_bar.dart';

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
  // 移动端访问历史:安卓返回键按此回退,耗尽后才允许退出应用。
  final TabNavHistory<SidebarItem> _navHistory = TabNavHistory<SidebarItem>();

  void _onOpenSyncRemoteFromSyncPage(SyncRemoteOpenRequest request) {
    setState(() => _pendingSyncRemoteOpen = request);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _selectItem(SidebarItem.fileManager);
    });
  }

  void _clearPendingSyncRemoteOpen() {
    if (_pendingSyncRemoteOpen == null) return;
    setState(() => _pendingSyncRemoteOpen = null);
  }

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

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
    // 首个页面进入历史;配置懒加载(默认值先行,加载差异经通知重建)。
    _navHistory.visit(widget.selectedItem);
    MobileNavPreferences.instance.load();
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

  /// 统一的导航入口:移动端把访问记入返回历史。
  void _selectItem(SidebarItem item) {
    if (_isAndroid) _navHistory.visit(item);
    widget.onSelectedItemChanged(item);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid) {
      return Scaffold(
        body: Row(
          children: [
            DesktopSidebar(
              selectedItem: _effectiveSelectedItem,
              sharesAvailable: _sharesAvailable,
              syncAvailable: _syncAvailable,
              onSelected: _selectItem,
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      );
    }
    return PopScope(
      // 有可回退页面时拦截系统返回;历史耗尽才允许退出应用。
      canPop: !_navHistory.canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final previous = _navHistory.back(
          (item) => MobileNavPreferences.instance.items.contains(item),
          current: _effectiveSelectedItem,
        );
        if (previous != null) {
          widget.onSelectedItemChanged(previous);
        } else {
          // 无可回退页面:重建让 canPop 重算,下一次系统返回即退出应用。
          setState(() {});
        }
      },
      child: Scaffold(
        body: _buildContent(),
        bottomNavigationBar: _buildMobileNavigation(),
      ),
    );
  }

  // Mobile bottom bar items/visibility/order are user-configurable in
  // Settings → 底部导航 (Android only); the config is the single source.
  Widget _buildMobileNavigation() {
    return ListenableBuilder(
      listenable: MobileNavPreferences.instance,
      builder: (context, _) {
        final items = MobileNavPreferences.instance.items;
        return MobileNavigationBar<SidebarItem>(
          accent: ThemeController.of(context).accent.color,
          selectedValue: _effectiveSelectedItem,
          onSelected: _selectItem,
          items: [
            for (final item in items)
              MobileNavItem(
                value: item,
                icon: item.icon,
                label: item.mobileLabel,
              ),
          ],
        );
      },
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
      SidebarItem.home => 7,
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
          onOpenAccountManagement: () => _selectItem(SidebarItem.storage),
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
        MobileHomePage(state: widget.state, onNavigate: _selectItem),
      ],
    );
  }
}
