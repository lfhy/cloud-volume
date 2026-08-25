part of 'settings_page.dart';

// Settings actions stay split out so the page widget itself remains readable.
extension _SettingsPageActions on _SettingsPageState {
  Future<void> _saveDownloadDirectory(
    RemoteStorageConfig config,
    String path,
  ) async {
    _updateState(() {
      _savingDownloadDirectory = true;
      _downloadDirectoryError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(defaultDownloadDirectory: path),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _downloadDirectoryError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingDownloadDirectory = false);
      }
    }
  }

  Future<void> _saveCacheDirectory(
    RemoteStorageConfig config,
    String path,
  ) async {
    _updateState(() {
      _savingCacheDirectory = true;
      _cacheDirectoryError = null;
    });
    try {
      await widget.api.saveConfig(config.copyWith(cacheDirectory: path));
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _cacheDirectoryError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingCacheDirectory = false);
      }
    }
  }

  Future<void> _saveHideDotFiles(
    RemoteStorageConfig config,
    bool hideDotFiles,
  ) async {
    _updateState(() {
      _savingVisibility = true;
      _visibilityError = null;
    });
    try {
      await widget.api.saveConfig(config.copyWith(hideDotFiles: hideDotFiles));
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _visibilityError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingVisibility = false);
      }
    }
  }

  Future<void> _saveTrashSettings(
    RemoteStorageConfig config,
    String directoryName,
    bool autoCleanupEnabled,
    int retentionDays,
  ) async {
    _updateState(() {
      _savingTrashSettings = true;
      _trashSettingsError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(
          trashDirectoryName: directoryName,
          trashRetentionDays: autoCleanupEnabled ? retentionDays : -1,
        ),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _trashSettingsError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingTrashSettings = false);
      }
    }
  }

  Future<void> _saveMountMetadataCacheEnabled(
    RemoteStorageConfig config,
    bool enabled,
  ) async {
    if (enabled == config.mountMetadataCacheEnabled) {
      return;
    }
    _updateState(() {
      _savingMountMetadataCache = true;
      _mountMetadataCacheError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(
          mountMetadataCacheSeconds: enabled
              ? config.effectiveMountMetadataCacheSeconds
              : -1,
        ),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _mountMetadataCacheError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingMountMetadataCache = false);
      }
    }
  }

  Future<void> _saveMountMetadataCacheSeconds(
    RemoteStorageConfig config,
    int seconds,
  ) async {
    if (seconds == config.effectiveMountMetadataCacheSeconds &&
        config.mountMetadataCacheEnabled) {
      return;
    }
    _updateState(() {
      _savingMountMetadataCache = true;
      _mountMetadataCacheError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(mountMetadataCacheSeconds: seconds),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _mountMetadataCacheError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingMountMetadataCache = false);
      }
    }
  }

  Future<void> _saveWritebackQuietSeconds(
    RemoteStorageConfig config,
    int seconds,
  ) async {
    if (seconds == config.writebackQuietSeconds) {
      return;
    }
    _updateState(() {
      _savingWritebackQuietSeconds = true;
      _writebackQuietSecondsError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(writebackQuietSeconds: seconds),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _writebackQuietSecondsError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingWritebackQuietSeconds = false);
      }
    }
  }

  Future<void> _saveWebdavCredentials(
    RemoteStorageConfig config,
    String username,
    String password,
  ) async {
    if (username.isEmpty || (password.isEmpty && !config.hasWebdavPassword)) {
      _updateState(() => _webdavCredentialsError = 'WebDAV 账号和密码不能为空。');
      return;
    }
    _updateState(() {
      _savingWebdavCredentials = true;
      _webdavCredentialsError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(
          webdavUsername: username,
          webdavPassword: password,
          hasWebdavPassword: config.hasWebdavPassword,
        ),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _webdavCredentialsError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingWebdavCredentials = false);
      }
    }
  }

  Future<void> _saveWindowsWritebackConcurrency(
    RemoteStorageConfig config,
    int value,
  ) async {
    if (value == config.windowsWritebackConcurrency) {
      return;
    }
    _updateState(() {
      _savingWindowsWritebackConcurrency = true;
      _windowsWritebackConcurrencyError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(windowsWritebackConcurrency: value),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _windowsWritebackConcurrencyError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingWindowsWritebackConcurrency = false);
      }
    }
  }

  Future<void> _forceResetWindowsMounts() async {
    _updateState(() {
      _resettingWindowsMounts = true;
      _windowsMountResetError = null;
    });
    try {
      await widget.api.cleanupMounts();
      if (!mounted) return;
      showAppToast(
        context,
        title: '挂载状态已重置',
        message: '已强制清理 Windows 挂载与残留 sync root。',
      );
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _windowsMountResetError = error.toString());
      showAppErrorToast(context, title: '挂载重置失败', message: error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _resettingWindowsMounts = false);
      }
    }
  }

  Future<void> _cleanupStaleWindowsProcesses() async {
    _updateState(() {
      _cleaningStaleWindowsProcesses = true;
      _windowsMountResetError = null;
    });
    try {
      final count = await widget.api.cleanupStaleWindowsProcesses();
      if (!mounted) return;
      showAppToast(
        context,
        title: '残留进程已清理',
        message: count > 0 ? '已结束 $count 个残留云卷进程。' : '没有发现需要清理的残留云卷进程。',
      );
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _windowsMountResetError = error.toString());
      showAppErrorToast(context, title: '清理残留进程失败', message: error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _cleaningStaleWindowsProcesses = false);
      }
    }
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
      if (!mounted) {
        return;
      }
      widget.onRefresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppErrorToast(context, title: '退出登录失败', message: error.toString());
    }
  }

  Future<void> _resetUserConfig() async {
    _updateState(() {
      _resettingUserConfig = true;
      _resetUserConfigError = null;
    });
    try {
      await widget.api.resetUserConfig();
      if (!mounted) return;
      showAppToast(context, title: '账号已重置', message: '已清空全部账号信息，即将返回初始化配置页。');
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _resetUserConfigError = error.toString());
      showAppErrorToast(context, title: '账号重置失败', message: error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _resettingUserConfig = false);
      }
    }
  }

  // --- Cache maintenance actions ---

  Future<void> refreshCacheStats(RemoteStorageConfig config) async {
    if (_loadingCacheStats) {
      return;
    }
    _updateState(() {
      _loadingCacheStats = true;
      _cacheDirectoryError = null;
    });
    try {
      final stats = await widget.api.getCacheStats(config);
      if (!mounted) return;
      _updateState(() => _cacheStats = stats);
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _cacheDirectoryError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _loadingCacheStats = false);
      }
    }
  }

  Future<void> openCacheDirectory(RemoteStorageConfig config) async {
    _updateState(() {
      _openingCache = true;
      _cacheDirectoryError = null;
    });
    try {
      await widget.api.openCacheDirectory(config);
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _cacheDirectoryError = error.toString());
      showAppErrorToast(context, title: '打开缓存目录失败', message: error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _openingCache = false);
      }
    }
  }

  Future<void> cleanCache(
    RemoteStorageConfig config, {
    required bool clearAll,
  }) async {
    _updateState(() {
      _cleaningCache = true;
      _cacheDirectoryError = null;
    });
    try {
      final result = await widget.api.cleanCache(config, clearAll: clearAll);
      if (!mounted) return;
      await refreshCacheStats(config);
      if (!mounted) return;
      final protected = result.skippedProtected > 0
          ? ' 已保留 ${result.skippedProtected} 个待同步数据块。'
          : '';
      showAppToast(
        context,
        title: clearAll
            ? (result.skippedProtected == 0 ? '缓存已清空' : '缓存清理完成')
            : '缓存已按规则清理',
        message: result.removed == 0
            ? '当前没有可清理的缓存。$protected'
            : '已删除 ${result.removed} 个文件，释放 ${_humanizeBytes(result.freedBytes)}。$protected',
      );
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _cacheDirectoryError = error.toString());
      showAppErrorToast(context, title: '清理缓存失败', message: error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _cleaningCache = false);
      }
    }
  }

  Future<void> saveCacheAutoCleanup(
    RemoteStorageConfig config,
    bool enabled,
  ) async {
    _updateState(() {
      _savingCacheRules = true;
      _cacheRulesError = null;
    });
    try {
      await widget.api.saveConfig(
        config.copyWith(cacheAutoCleanupEnabled: enabled),
      );
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _cacheRulesError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingCacheRules = false);
      }
    }
  }

  Future<void> saveCacheMaxSize(RemoteStorageConfig config, int size) async {
    _updateState(() {
      _savingCacheRules = true;
      _cacheRulesError = null;
    });
    try {
      await widget.api.saveConfig(config.copyWith(cacheMaxSizeMb: size));
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _cacheRulesError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingCacheRules = false);
      }
    }
  }

  Future<void> saveCacheMaxAge(RemoteStorageConfig config, int age) async {
    _updateState(() {
      _savingCacheRules = true;
      _cacheRulesError = null;
    });
    try {
      await widget.api.saveConfig(config.copyWith(cacheMaxAgeDays: age));
      if (!mounted) return;
      widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _cacheRulesError = error.toString());
    } finally {
      if (mounted) {
        _updateState(() => _savingCacheRules = false);
      }
    }
  }

  static String _humanizeBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return size >= 100 || unit == 0
        ? '${size.toStringAsFixed(0)} ${units[unit]}'
        : '${size.toStringAsFixed(2)} ${units[unit]}';
  }
}
