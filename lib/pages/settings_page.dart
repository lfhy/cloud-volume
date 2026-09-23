// 设置页负责按“常规 / 存储 / 网络 / 账号 / Windows / 关于”分组展示配置，
// 避免平台专属选项和过多通用设置挤在同一长页里。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/utils/app_runtime_version.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/mobile_settings_navigation.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/mobile_page_chrome.dart';
import 'package:remote_storage/widgets/settings_about_section.dart';
import 'package:remote_storage/widgets/settings_reset_user_config_section.dart';
import 'package:remote_storage/widgets/settings_sections.dart'
    show
        DownloadDirectorySection,
        ThemePicker,
        VisibilitySection,
        WebDavCredentialsSection;
import 'package:remote_storage/widgets/settings_cache_section.dart';
import 'package:remote_storage/widgets/settings_config_backup_section.dart';
import 'package:remote_storage/widgets/settings_log_section.dart';
import 'package:remote_storage/widgets/settings_mobile_nav_section.dart';
import 'package:remote_storage/widgets/settings_p2p_section.dart';
import 'package:remote_storage/widgets/settings_proxy_section.dart';
import 'package:remote_storage/widgets/settings_sync_section.dart';
import 'package:remote_storage/widgets/settings_trash_section.dart';
import 'package:remote_storage/widgets/settings_update_section.dart';
import 'package:remote_storage/widgets/windows_settings_sections.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'settings_page_actions.dart';
part 'settings_page_layout.dart';
part 'settings_page_poll_actions.dart';
part 'settings_page_sections.dart';
part 'settings_page_windows_mount_actions.dart';

/// Each enum value identifies a settings card that can be reached from the
/// left-side anchor rail.
enum _SettingsTab {
  // 常规 group: 应用外观、版本、日志
  update,
  appearance,
  logging,
  // 移动端专属 group: 底部导航(仅 Android 渲染)
  mobileNav,
  // 网络 group: 代理、WebDAV 凭据
  proxy,
  webdav,
  p2p,
  // 存储 group: 下载、缓存、显示、同步、回收站
  download,
  cache,
  visibility,
  sync,
  trash,
  // 账号 group: 重置、备份、配置管理
  resetAccount,
  configBackup,
  configManage,
  // Windows group
  windowsWriteback,
  windowsMount,
  // 关于 group
  about,
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.state,
    required this.api,
    required this.onEditConfig,
    required this.onRefresh,
    this.mobileNavigation,
  });

  final BootstrapState state;
  final RemoteStorageGateway api;
  final VoidCallback onEditConfig;
  final VoidCallback onRefresh;

  /// Android-only back-stack hook owned by the shell; when set, the page
  /// reports detail/index transitions so system Back can collapse the
  /// detail page before falling through to tab history.
  final MobileSettingsNavigation? mobileNavigation;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ScrollController _contentScrollController = ScrollController();
  final Map<_SettingsTab, GlobalKey> _sectionKeys = {
    for (final tab in _SettingsTab.values) tab: GlobalKey(),
  };
  bool _savingDownloadDirectory = false;
  String? _downloadDirectoryError;
  bool _savingCacheDirectory = false;
  String? _cacheDirectoryError;
  CacheStats? _cacheStats;
  bool _loadingCacheStats = false;
  bool _cleaningCache = false;
  bool _openingCache = false;
  bool _savingCacheRules = false;
  String? _cacheRulesError;
  bool _savingVisibility = false;
  String? _visibilityError;
  bool _savingTrashSettings = false;
  String? _trashSettingsError;
  bool _savingWritebackQuietSeconds = false;
  String? _writebackQuietSecondsError;
  bool _savingMountMetadataCache = false;
  String? _mountMetadataCacheError;
  bool _savingMountRemotePollInterval = false;
  String? _mountRemotePollIntervalError;
  bool _savingWebdavCredentials = false;
  String? _webdavCredentialsError;
  bool _savingWindowsWritebackConcurrency = false;
  String? _windowsWritebackConcurrencyError;
  bool _savingWindowsMountEngine = false;
  String? _windowsMountEngineError;
  bool _winFspAvailable = false;
  bool _installingWindowsWinFsp = false;
  bool _resettingWindowsMounts = false;
  String? _windowsMountResetError;
  bool _cleaningStaleWindowsProcesses = false;
  bool _resettingUserConfig = false;
  String? _resetUserConfigError;
  _SettingsTab? _mobileTab;

  /// Single mutation entry for the Android detail/index split. While a
  /// detail page is open its collapse callback stays bound on the shell
  /// navigation so system Back reaches it before tab history.
  void _selectMobileTab(_SettingsTab? tab) {
    setState(() => _mobileTab = tab);
    if (tab != null) {
      widget.mobileNavigation?.bind(_collapseMobileDetail);
    } else {
      widget.mobileNavigation?.clear();
    }
  }

  void _collapseMobileDetail() => _selectMobileTab(null);

  bool get _showsWindowsTab => isWindowsPlatform;

  void _updateState(VoidCallback action) => setState(action);

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final config = widget.state.config;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    if (isAndroid) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: _buildAndroidSettings(theme, config),
        ),
      );
    }
    // Two-column layout: vertical group rail on the left, scrolling content
    // on the right. The group rail replaces the former top ShadTabs bar so
    // all settings categories are reachable without horizontal scrolling.
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: _buildDesktopSettings(theme, config),
    );
  }

  Widget _buildAndroidSettings(ShadThemeData theme, RemoteStorageConfig config) {
    if (_mobileTab == null) {
      return _buildMobileSettingsIndex(theme);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppTooltip(
              message: '返回设置',
              child: ShadIconButton.ghost(
                width: 48,
                height: 48,
                iconSize: 20,
                icon: Icon(
                  LucideIcons.chevronLeft,
                  color: theme.colorScheme.foreground,
                ),
                onPressed: () => _selectMobileTab(null),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tabLabel(_mobileTab!),
                    style: theme.textTheme.h3.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 23,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _mobileDetailSubtitle(_mobileTab!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.mutedForeground,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            controller: _contentScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildContentForTab(theme, config, _mobileTab!),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSettings(ShadThemeData theme, RemoteStorageConfig config) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Left sidebar: title + vertical group navigation ---
            SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '设置',
                    style: theme.textTheme.h3.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(child: _buildGroupRail(theme)),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // --- Right content area ---
            Expanded(
              child: SingleChildScrollView(
                controller: _contentScrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._buildAllContent(theme, config),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The rail-group header the tab belongs to doubles as the detail-page
  /// subtitle, expressing scope without repeating the title.
  String _mobileDetailSubtitle(_SettingsTab tab) {
    for (final group in _railGroups()) {
      if (group.tabs.contains(tab)) return group.header;
    }
    return '设置';
  }

  Widget _buildMobileSettingsIndex(ShadThemeData theme) {
    final groups = _railGroups();
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        MobilePageHeader(
          title: '设置',
          subtitle: '管理应用与连接偏好。',
        ),
        const SizedBox(height: 6),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 14, bottom: 6),
            child: Text(group.header, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.mutedForeground)),
          ),
          // 移动索引分组恢复带边框卡片(用户裁决;无边框基线仅适用于
          // 文件/回收站/任务列表页)。
          ShadCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < group.tabs.length; i++) ...[
                  // ShadCard's DecoratedBox hides ListTile ink; a transparent
                  // Material restores the visible press feedback on touch.
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      dense: true,
                      title: Text(_tabLabel(group.tabs[i])),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _selectMobileTab(group.tabs[i]),
                    ),
                  ),
                  if (i != group.tabs.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCard(ShadThemeData theme, String title, Widget child) {
    // 详情分区恢复带边框卡片(用户裁决;无边框基线仅适用于文件/回收站/
    // 任务列表页),移动与桌面同款。
    return SizedBox(
      width: double.infinity,
      child: ShadCard(
        padding: const EdgeInsets.all(20),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: theme.colorScheme.foreground,
          ),
        ),
        child: child,
      ),
    );
  }

  Future<void> _pickDownloadDirectory(RemoteStorageConfig config) async {
    final initialDirectory = await resolveDefaultDownloadDirectory(
      config.defaultDownloadDirectory,
    );
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择默认下载目录',
      initialDirectory: initialDirectory,
    );
    if (path == null || path.trim().isEmpty) {
      return;
    }
    await _saveDownloadDirectory(config, path.trim());
  }

  Future<void> _resetDownloadDirectory(RemoteStorageConfig config) async {
    await _saveDownloadDirectory(config, '');
  }

  Future<void> _pickCacheDirectory(RemoteStorageConfig config) async {
    final initialDirectory = config.resolvedCacheDirectory.trim().isNotEmpty
        ? config.resolvedCacheDirectory.trim()
        : null;
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择缓存目录',
      initialDirectory: initialDirectory,
    );
    if (path == null || path.trim().isEmpty) {
      return;
    }
    await _saveCacheDirectory(config, path.trim());
  }

  Future<void> _resetCacheDirectory(RemoteStorageConfig config) async {
    await _saveCacheDirectory(config, '');
  }

  @override
  void dispose() {
    widget.mobileNavigation?.clear();
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load cache stats once the page is mounted so the card shows real usage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshCacheStats(widget.state.config);
    });
    _refreshWindowsWinFspAvailability();
  }

  Future<void> _refreshWindowsWinFspAvailability() async {
    if (!isWindowsPlatform) return;
    if (widget.api is! WindowsWinFspQuery) return;
    try {
      final available = await (widget.api as WindowsWinFspQuery)
          .listWindowsWinFspAvailable();
      if (!mounted) return;
      setState(() => _winFspAvailable = available);
    } catch (_) {
      // Availability probe is best-effort; leave the selector on Cloud Files.
    }
  }
}
