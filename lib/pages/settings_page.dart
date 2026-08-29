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
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:remote_storage/widgets/app_toast.dart';
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
  });

  final BootstrapState state;
  final RemoteStorageGateway api;
  final VoidCallback onEditConfig;
  final VoidCallback onRefresh;

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

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      // Two-column layout: vertical group rail on the left, scrolling content
      // on the right. The group rail replaces the former top ShadTabs bar so
      // all settings categories are reachable without horizontal scrolling.
      child: LayoutBuilder(builder: (context, constraints) {
        if (isAndroid) {
          if (_mobileTab == null) {
            return _buildMobileSettingsIndex(theme);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconButton(
                  tooltip: '返回设置',
                  onPressed: () => setState(() => _mobileTab = null),
                  icon: const Icon(Icons.arrow_back),
                ),
                Text(_tabLabel(_mobileTab!), style: theme.textTheme.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 22)),
              ]),
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
      }),
    );
  }

  Widget _buildMobileSettingsIndex(ShadThemeData theme) {
    final groups = _railGroups();
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Text('设置', style: theme.textTheme.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 28)),
        const SizedBox(height: 18),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 14, bottom: 6),
            child: Text(group.header, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.mutedForeground)),
          ),
          ShadCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < group.tabs.length; i++) ...[
                  ListTile(
                    dense: true,
                    title: Text(_tabLabel(group.tabs[i])),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _mobileTab = group.tabs[i]),
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
