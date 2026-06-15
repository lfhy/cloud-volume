// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页挂载逻辑：刷新状态，并暴露挂载、卸载和打开挂载目录动作。

extension _FileManagerPageMount on _FileManagerPageState {
  void _showMountUnavailableMessage([FileManagerBucketEntry? bucket]) {
    final entry = bucket ?? _activeBucketEntry;
    final bucketLabel = entry?.bucket.name.trim() ?? '';
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
    final mountedBucket = _currentMountedBucketEntry();
    if (mountedBucket == null) {
      return;
    }
    await _refreshMountStatus(mountedBucket);
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

  FileManagerBucketEntry? _currentMountedBucketEntry() {
    final buckets = _buckets;
    if (buckets == null) {
      return null;
    }
    for (final bucket in buckets) {
      if (_bucketMountStatuses[bucket.id]?.mounted == true) {
        return bucket;
      }
    }
    return null;
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
    final options = await showMountBucketDialog(
      context,
      bucket: targetBucket.bucket.name,
    );
    if (options == null) {
      return;
    }
    setState(() => _mountBusyBuckets.add(targetBucket.id));
    try {
      final status = await widget.api.mountBucket(
        targetBucket.config,
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
    setState(() => _mountBusyBuckets.add(targetBucket.id));
    try {
      final status = await widget.api.unmountBucket(targetBucket.bucket.name);
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
      if (status.mounted) {
        final keys = _bucketMountStatuses.keys.toList();
        for (final key in keys) {
          final existing = _bucketMountStatuses[key];
          if (existing == null || key == bucketId) {
            continue;
          }
          _bucketMountStatuses[key] = BucketMountStatus(
            mounted: false,
            bucket: existing.bucket,
            mountPath: existing.mountPath,
            serverUrl: existing.serverUrl,
            port: existing.port,
            lastError: existing.lastError,
          );
        }
      }
      _bucketMountStatuses[bucketId] = status;
    });
  }
}
