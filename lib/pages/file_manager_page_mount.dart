// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页挂载逻辑：刷新状态，并暴露挂载、卸载和打开挂载目录动作。

extension _FileManagerPageMount on _FileManagerPageState {
  void _showMountUnavailableMessage([FileManagerBucketEntry? bucket]) {
    final entry = bucket ?? _activeBucketEntry;
    final bucketLabel = entry?.label.trim() ?? '';
    final title = bucketLabel.isEmpty ? '挂载不可用' : '“$bucketLabel”暂时不能挂载';
    final message = !widget.api.capabilities.supportsMounts
        ? '当前运行环境暂不支持桌面挂载。'
        : '当前账号暂不支持桌面挂载。';
    _showPageMessage(title: title, message: message);
  }

  Widget _buildContentWithMountLoading(ShadThemeData theme) {
    final content = _buildContent(theme);
    if (_mountBusyBuckets.isEmpty) {
      return content;
    }
    final color = theme.colorScheme.primary;
    return Stack(
      children: [
        content,
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.background.withValues(alpha: 0.42),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.border.withValues(alpha: 0.82),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: AppLoadingIndicator(
                          strokeWidth: 1.8,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '正在处理挂载，请稍候…',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _refreshVisibleMountStatuses() async {
    if (!widget.api.capabilities.supportsMounts) {
      return;
    }
    if (_loading ||
        _mountStatusRefreshInFlight ||
        _mountBusyBuckets.isNotEmpty) {
      return;
    }
    _mountStatusRefreshInFlight = true;
    try {
      await _refreshVisibleMountStatusesOnce();
    } finally {
      _mountStatusRefreshInFlight = false;
    }
  }

  Future<void> _refreshVisibleMountStatusesOnce() async {
    if (!widget.api.capabilities.supportsMounts) {
      return;
    }
    if (_activeBucketEntry != null) {
      final activeStatus = _bucketMountStatuses[_activeBucketId!];
      if (activeStatus?.mounted == true ||
          _mountBusyBuckets.contains(_activeBucketId!)) {
        await _refreshMountStatus(_activeBucketEntry!);
      }
      return;
    }
    final buckets = _buckets;
    if (buckets == null) {
      return;
    }
    for (final bucket in buckets) {
      if (_bucketMountStatuses[bucket.id]?.mounted == true ||
          _mountBusyBuckets.contains(bucket.id)) {
        await _refreshMountStatus(bucket);
      }
    }
  }

  Future<void> _refreshBucketMountStatuses(
    List<FileManagerBucketEntry> buckets,
  ) async {
    if (!widget.api.capabilities.supportsMounts) {
      return;
    }
    for (final bucket in buckets) {
      if (!bucket.config.supportsMounts) {
        continue;
      }
      await _refreshMountStatus(bucket);
    }
  }

  Future<void> _refreshMountStatus(FileManagerBucketEntry bucket) async {
    if (!widget.api.capabilities.supportsMounts ||
        !bucket.config.supportsMounts) {
      return;
    }
    try {
      final status = await widget.api.getBucketMountStatus(bucket.bucket.name);
      if (!mounted) return;
      _applyMountStatus(bucket.id, status);
    } catch (_) {
      // 挂载状态查询失败不阻断文件浏览；用户显式操作时再显示错误。
    }
  }

  Future<void> _mountBucket([FileManagerBucketEntry? bucket]) async {
    final targetBucket = bucket ?? _activeBucketEntry;
    if (targetBucket == null || _mountBusyBuckets.contains(targetBucket.id)) {
      return;
    }
    if (!targetBucket.config.supportsMounts) {
      _showMountUnavailableMessage(targetBucket);
      return;
    }
    final config = targetBucket.config;
    final forceReadOnly = config
        .bucketSettingsFor(targetBucket.bucket.name)
        .readOnly;
    var winFspInstalled =
        isWindowsPlatform &&
        widget.api is WindowsWinFspQuery &&
        await (widget.api as WindowsWinFspQuery).listWindowsWinFspAvailable();
    if (!mounted) return;
    final currentEngine = config.windowsMountEngine;
    final winFspEnabled =
        isWindowsPlatform && currentEngine == WindowsMountEngine.winFsp;
    if (winFspEnabled && !winFspInstalled) {
      final shouldInstall = await showAppConfirmModal(
        context: context,
        title: const Text('需要安装 WinFsp'),
        description: const Text(
          '当前挂载引擎为 WinFsp 虚拟文件系统，但本机尚未安装 WinFsp 驱动。应用已内嵌安装包，是否现在安装？（会弹出 UAC 确认）',
        ),
        confirmLabel: '安装并继续',
        cancelLabel: '取消',
      );
      if (shouldInstall != true) return;
      try {
        final installed = await (widget.api as WindowsWinFspQuery)
            .installWindowsWinFsp();
        if (!mounted) return;
        if (!installed) {
          _showPageMessage(
            title: 'WinFsp 安装未完成',
            message: '驱动仍不可见，可能需要重启后再试，或在设置中切换回 Cloud Files 引擎。',
          );
          return;
        }
        winFspInstalled = true;
      } catch (error) {
        _showPageError(error);
        return;
      }
    }
    // Cloud Files needs the Windows engine picker but is path-only. Querying
    // free letters still lets a newly selected read-only WinFsp mount complete
    // the install flow from this dialog.
    final showWindowsMountMode =
        isWindowsPlatform &&
        targetBucket.config.windowsMountMode != WindowsMountMode.webdav;
    var availableDriveLetters = const <String>[];
    if (showWindowsMountMode && widget.api is AvailableDriveLetterQuery) {
      try {
        availableDriveLetters = await (widget.api as AvailableDriveLetterQuery)
            .listAvailableDriveLetters();
      } catch (error) {
        _showPageError(error);
        return;
      }
    }
    if (!mounted) return;
    final options = await showMountBucketDialog(
      context,
      bucket: targetBucket.bucket.name,
      showWindowsMountMode: showWindowsMountMode,
      availableDriveLetters: availableDriveLetters,
      currentEngine: currentEngine,
      winFspAvailable: winFspInstalled,
      forceReadOnly: forceReadOnly,
    );
    if (options == null) {
      return;
    }
    if (!mounted) return;
    if (options.windowsMountEngine == WindowsMountEngine.winFsp &&
        !winFspInstalled) {
      final shouldInstall = await showAppConfirmModal(
        context: context,
        title: const Text('只读挂载需要 WinFsp'),
        description: const Text(
          'Cloud Files 只能阻止远端写回，无法在 Explorer 写入前拒绝操作。严格只读将使用 WinFsp；是否现在安装驱动？（会弹出 UAC 确认）',
        ),
        confirmLabel: '安装并继续',
        cancelLabel: '取消',
      );
      if (shouldInstall != true) return;
      try {
        final installed = await (widget.api as WindowsWinFspQuery)
            .installWindowsWinFsp();
        if (!mounted) return;
        if (!installed) {
          _showPageMessage(
            title: 'WinFsp 安装未完成',
            message: '严格只读挂载未启动；请安装 WinFsp 后重试。',
          );
          return;
        }
        winFspInstalled = true;
      } catch (error) {
        _showPageError(error);
        return;
      }
    }
    // Persist an engine change chosen from the mount dialog before mounting,
    // so the backend picks the right kernel and the setting sticks for next time.
    var mountConfig = targetBucket.config;
    if (options.windowsMountEngine != null &&
        options.windowsMountEngine != mountConfig.windowsMountEngine) {
      try {
        final updatedConfig = mountConfig.copyWith(
          windowsMountEngine: options.windowsMountEngine,
        );
        if (widget.profiles.isEmpty) {
          // The legacy single-account flow has no named profile yet.
          final saved = await widget.api.saveConfig(updatedConfig);
          mountConfig = saved.config;
        } else {
          // saveConfig always writes the "default" profile. Saving a bucket
          // from another account there cloned the account and duplicated its
          // buckets after the subsequent bootstrap refresh.
          await widget.api.saveProfile(targetBucket.profileName, updatedConfig);
          mountConfig = updatedConfig;
        }
        if (!mounted) return;
        widget.onRefresh();
      } catch (error) {
        _showPageError(error);
        return;
      }
    }
    setState(() => _mountBusyBuckets.add(targetBucket.id));
    try {
      final status = await widget.api.mountBucket(
        mountConfig,
        targetBucket.bucket.name,
        options,
      );
      if (!mounted) return;
      _applyMountStatus(targetBucket.id, status);
    } catch (error) {
      _showPageError(error);
    } finally {
      if (mounted) {
        setState(() => _mountBusyBuckets.remove(targetBucket.id));
      }
    }
  }

  Future<void> _unmountBucket([FileManagerBucketEntry? bucket]) async {
    final targetBucket = bucket ?? _activeBucketEntry;
    if (targetBucket == null || _mountBusyBuckets.contains(targetBucket.id)) {
      return;
    }
    final sourceListingViewGeneration = _listingViewGeneration;
    final inputGeneration = _mobileInputGeneration;
    if (!_isCurrentBucketCommand(
      targetBucket,
      sourceListingViewGeneration,
      inputGeneration,
    )) {
      return;
    }
    final choice = await showUnmountBucketDialog(
      context,
      bucket: targetBucket.bucket.name,
      canRemoveLocalCache:
          isWindowsPlatform &&
          targetBucket.config.windowsMountEngine ==
              WindowsMountEngine.cloudFiles,
    );
    if (choice == null ||
        !_isCurrentBucketCommand(
          targetBucket,
          sourceListingViewGeneration,
          inputGeneration,
        )) {
      return;
    }
    setState(() => _mountBusyBuckets.add(targetBucket.id));
    try {
      final status = await widget.api.unmountBucket(
        targetBucket.bucket.name,
        removeLocalCache: choice.removeLocalCache,
      );
      if (!mounted) return;
      _applyMountStatus(targetBucket.id, status);
      final cleanupError = status.lastError?.trim();
      if (cleanupError != null && cleanupError.isNotEmpty) {
        _showPageMessage(title: '卸载完成，但缓存未清理', message: cleanupError);
      }
    } catch (error) {
      _showPageError(error);
    } finally {
      if (mounted) {
        setState(() => _mountBusyBuckets.remove(targetBucket.id));
      }
    }
  }

  Future<void> _openMountedBucket([FileManagerBucketEntry? bucket]) async {
    final targetBucket = bucket ?? _activeBucketEntry;
    if (targetBucket == null) return;
    try {
      final status = await widget.api.openBucketMount(targetBucket.bucket.name);
      if (!mounted) return;
      _applyMountStatus(targetBucket.id, status);
    } catch (error) {
      _showPageError(error);
    }
  }

  void _applyMountStatus(String bucketId, BucketMountStatus status) {
    if (!widget.api.capabilities.supportsMounts) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _bucketMountStatuses[bucketId] = status;
    });
  }
}
