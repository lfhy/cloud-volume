// 设置页负责按“通用 / Windows / 关于”分组展示配置，避免平台专属选项把通用设置挤在同一长页里。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/utils/app_runtime_version.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/default_download_directory.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/settings_about_section.dart';
import 'package:remote_storage/widgets/settings_sections.dart'
    show
        CacheCleanupSection,
        DownloadDirectorySection,
        CacheDirectorySection,
        ThemePicker,
        VisibilitySection,
        WebDavCredentialsSection;
import 'package:remote_storage/widgets/settings_sync_section.dart';
import 'package:remote_storage/widgets/settings_trash_section.dart';
import 'package:remote_storage/widgets/settings_update_section.dart';
import 'package:remote_storage/widgets/windows_settings_sections.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'settings_page_actions.dart';

enum _SettingsTab { general, windows, about }

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
  _SettingsTab _activeTab = _SettingsTab.general;
  bool _savingDownloadDirectory = false;
  String? _downloadDirectoryError;
  bool _savingCacheDirectory = false;
  String? _cacheDirectoryError;
  bool _savingVisibility = false;
  String? _visibilityError;
  bool _savingTrashSettings = false;
  String? _trashSettingsError;
  bool _savingWritebackQuietSeconds = false;
  String? _writebackQuietSecondsError;
  bool _savingMountMetadataCache = false;
  String? _mountMetadataCacheError;
  bool _savingWebdavCredentials = false;
  String? _webdavCredentialsError;
  bool _savingWindowsMountMode = false;
  String? _windowsMountModeError;
  bool _savingWindowsThisPcEntry = false;
  String? _windowsThisPcEntryError;
  bool _savingWindowsWritebackConcurrency = false;
  String? _windowsWritebackConcurrencyError;
  bool _resettingWindowsMounts = false;
  String? _windowsMountResetError;
  bool _cleaningStaleWindowsProcesses = false;

  bool get _showsWindowsTab => isWindowsPlatform;

  bool get _showsFooterActions => _activeTab != _SettingsTab.about;

  void _updateState(VoidCallback action) => setState(action);

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final config = widget.state.config;

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: SingleChildScrollView(
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
            const SizedBox(height: 6),
            Text(
              '管理远程存储的连接配置、下载目录、界面偏好和挂载行为。',
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            ShadTabs<_SettingsTab>(
              value: _activeTab,
              onChanged: (value) => setState(() => _activeTab = value),
              tabs: [
                ShadTab<_SettingsTab>(
                  value: _SettingsTab.general,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildGeneralSections(theme, config),
                  ),
                  child: const Text('通用设置'),
                ),
                if (_showsWindowsTab)
                  ShadTab<_SettingsTab>(
                    value: _SettingsTab.windows,
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildWindowsSections(theme, config),
                    ),
                    child: const Text('Windows 设置'),
                  ),
                ShadTab<_SettingsTab>(
                  value: _SettingsTab.about,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildAboutSections(theme),
                  ),
                  child: const Text('关于'),
                ),
              ],
            ),
            if (_showsFooterActions) ...[
              const SizedBox(height: 24),
              _buildFooterActions(),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGeneralSections(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    final sections = <Widget>[
      _buildCard(
        theme,
        '应用更新',
        SettingsUpdateSection(theme: theme, currentVersion: kAppRuntimeVersion),
      ),
      const SizedBox(height: 20),
      _buildCard(theme, '外观', const ThemePicker()),
      if (widget.api.capabilities.supportsDownloadDirectory) ...[
        const SizedBox(height: 20),
        _buildCard(
          theme,
          '下载设置',
          DownloadDirectorySection(
            theme: theme,
            configuredPath: config.defaultDownloadDirectory,
            saving: _savingDownloadDirectory,
            errorText: _downloadDirectoryError,
            onPickDirectory: () => _pickDownloadDirectory(config),
            onResetDirectory: () => _resetDownloadDirectory(config),
          ),
        ),
      ],
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '缓存设置',
        CacheDirectorySection(
          theme: theme,
          displayPath: config.resolvedCacheDirectory,
          hasCustomPath: config.cacheDirectory.trim().isNotEmpty,
          saving: _savingCacheDirectory,
          errorText: _cacheDirectoryError,
          onPickDirectory: () => _pickCacheDirectory(config),
          onResetDirectory: () => _resetCacheDirectory(config),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '缓存管理',
        CacheCleanupSection(
          theme: theme,
          onClearMountCache: () => _clearMountCache(),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '显示设置',
        VisibilitySection(
          theme: theme,
          hideDotFiles: config.hideDotFiles,
          saving: _savingVisibility,
          errorText: _visibilityError,
          onChanged: (value) => _saveHideDotFiles(config, value),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '同步设置',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WritebackQuietSecondsSection(
              theme: theme,
              seconds: config.writebackQuietSeconds,
              saving: _savingWritebackQuietSeconds,
              errorText: _writebackQuietSecondsError,
              onChanged: (value) => _saveWritebackQuietSeconds(config, value),
            ),
            const SizedBox(height: 20),
            MountMetadataCacheSection(
              theme: theme,
              enabled: config.mountMetadataCacheEnabled,
              seconds: config.effectiveMountMetadataCacheSeconds,
              saving: _savingMountMetadataCache,
              errorText: _mountMetadataCacheError,
              onEnabledChanged: (value) =>
                  _saveMountMetadataCacheEnabled(config, value),
              onSecondsChanged: (value) =>
                  _saveMountMetadataCacheSeconds(config, value),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        '回收站',
        TrashSettingsSection(
          theme: theme,
          directoryName: config.trashDirectoryName,
          autoCleanupEnabled: config.trashAutoCleanupEnabled,
          retentionDays: config.effectiveTrashRetentionDays,
          saving: _savingTrashSettings,
          errorText: _trashSettingsError,
          onSave: (directoryName, autoCleanupEnabled, retentionDays) =>
              _saveTrashSettings(
                config,
                directoryName,
                autoCleanupEnabled,
                retentionDays,
              ),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        'WebDAV 凭据',
        WebDavCredentialsSection(
          theme: theme,
          username: config.webdavUsername,
          hasPassword: config.hasWebdavPassword,
          saving: _savingWebdavCredentials,
          errorText: _webdavCredentialsError,
          onSave: (username, password) =>
              _saveWebdavCredentials(config, username, password),
        ),
      ),
    ];
    return sections;
  }

  List<Widget> _buildWindowsSections(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    return [
      _buildCard(
        theme,
        'Windows 挂载模式',
        WindowsMountModeSection(
          theme: theme,
          mode: config.windowsMountMode,
          saving: _savingWindowsMountMode,
          errorText: _windowsMountModeError,
          onChanged: (value) => _saveWindowsMountMode(config, value),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        'Windows 入口',
        WindowsThisPcEntrySection(
          theme: theme,
          enabled: config.windowsThisPcEntryEnabled,
          saving: _savingWindowsThisPcEntry,
          errorText: _windowsThisPcEntryError,
          onChanged: (value) => _saveWindowsThisPcEntry(config, value),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        'Windows 写回并发',
        WindowsWritebackConcurrencySection(
          theme: theme,
          concurrency: config.windowsWritebackConcurrency,
          saving: _savingWindowsWritebackConcurrency,
          errorText: _windowsWritebackConcurrencyError,
          onChanged: (value) => _saveWindowsWritebackConcurrency(config, value),
        ),
      ),
      const SizedBox(height: 20),
      _buildCard(
        theme,
        'Windows 挂载恢复',
        WindowsMountRecoverySection(
          theme: theme,
          busy: _resettingWindowsMounts,
          cleaningProcesses: _cleaningStaleWindowsProcesses,
          errorText: _windowsMountResetError,
          onReset: _forceResetWindowsMounts,
          onCleanupProcesses: _cleanupStaleWindowsProcesses,
        ),
      ),
    ];
  }

  List<Widget> _buildAboutSections(ShadThemeData theme) {
    return [
      _buildCard(
        theme,
        '关于云卷',
        SettingsAboutSection(theme: theme, versionText: kAppRuntimeVersion),
      ),
    ];
  }

  Widget _buildFooterActions() {
    return Row(
      children: [
        ShadButton(onPressed: widget.onEditConfig, child: const Text('重新配置')),
        const SizedBox(width: 10),
        ShadButton.outline(
          onPressed: widget.onRefresh,
          child: const Text('刷新状态'),
        ),
        if (widget.api.capabilities.supportsSessionLogin) ...[
          const SizedBox(width: 10),
          ShadButton.outline(onPressed: _logout, child: const Text('退出登录')),
        ],
      ],
    );
  }

  Widget _buildCard(ShadThemeData theme, String title, Widget child) {
    return ShadCard(
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
}
