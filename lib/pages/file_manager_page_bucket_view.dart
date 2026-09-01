part of 'file_manager_page.dart';

// 文件管理页桶列表视图：把桶级按钮和空态渲染从主页面文件中拆出。

extension _FileManagerPageBucketView on _FileManagerPageState {
  Widget _buildBucketView(ShadThemeData theme) {
    if (_buckets == null) return const SizedBox();
    final buckets = _filteredBuckets;
    final warning = _buildUnavailableSourceWarning(theme);
    if (buckets.isEmpty) {
      return Column(
        children: [
          ?warning,
          Expanded(
            child: FileManagerEmptyState(
              theme: theme,
              icon: LucideIcons.database,
              text: _hasSearchQuery ? '没有匹配的存储桶' : '没有可用的存储桶',
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        ?warning,
        Expanded(
          child: FileManagerBucketBrowser(
            buckets: buckets,
            isGrid: _usesMobileNavigation ? false : _isGrid,
            mobilePresentation: _usesMobileNavigation,
            gridIconSize: _FileManagerPageState._bucketGridIconSize,
            listIconSize: _FileManagerPageState._listIconSize,
            onOpenBucket: (bucket) =>
                unawaited(_openPresentationBucket(bucket)),
            mountStatuses: _usesMobileNavigation || _isTrashHome
                ? const <String, BucketMountStatus>{}
                : _bucketMountStatuses,
            busyBuckets: _usesMobileNavigation || _isTrashHome
                ? const <String>{}
                : _mountBusyBuckets,
            showActionColumn: !_isTrashHome,
            onOpenTrashBucket: _isTrashHome
                ? null
                : (bucket) => unawaited(_openPresentationTrash(bucket)),
            onConfigureBucket: _isTrashHome
                ? null
                : (bucket) => unawaited(_configureBucket(bucket)),
            onMountBucket: _usesMobileNavigation || _isTrashHome
                ? null
                : widget.api.capabilities.supportsMounts
                ? (bucket) => unawaited(_mountBucket(bucket))
                : (bucket) => _showMountUnavailableMessage(bucket),
            onUnmountBucket: _usesMobileNavigation || _isTrashHome
                ? null
                : widget.api.capabilities.supportsMounts
                ? (bucket) => unawaited(_unmountBucket(bucket))
                : null,
            onOpenMountedBucket: _usesMobileNavigation || _isTrashHome
                ? null
                : widget.api.capabilities.supportsMounts
                ? (bucket) => unawaited(_openMountedBucket(bucket))
                : null,
            onOpenWebDavBucket: _isTrashHome
                ? null
                : widget.api.capabilities.supportsWebDavAccess
                ? (bucket) => _showWebDavEntry(bucket)
                : null,
            bucketTrashEnabled: _bucketTrashEnabled,
            webDavActionLabel: 'WebDAV',
            onReorder: (_isTrashHome || _isGrid || _hasSearchQuery)
                ? null
                : _reorderBuckets,
          ),
        ),
      ],
    );
  }

  Widget? _buildUnavailableSourceWarning(ShadThemeData theme) {
    if (_unavailableBucketSources.isEmpty) return null;
    final first = _unavailableBucketSources.first;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 17,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_unavailableBucketSources.length} 个账号暂时无法访问；其余账号仍可正常使用。',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.foreground,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ShadButton.outline(
            onPressed: () {
              _reconfigureUnavailableBucketSource(first.profileName);
            },
            child: const Text('重新配置'),
          ),
        ],
      ),
    );
  }

  Future<void> _reorderBuckets(int oldIndex, int newIndex) async {
    final current = List<FileManagerBucketEntry>.from(_buckets ?? const []);
    if (oldIndex < 0 || oldIndex >= current.length) {
      return;
    }
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= current.length) {
      return;
    }
    final moved = current.removeAt(oldIndex);
    current.insert(targetIndex, moved);
    _replaceBucketsAfterReorder(current);
    try {
      await widget.api.reorderBuckets(
        current.map((entry) => entry.id).toList(growable: false),
      );
    } catch (error) {
      if (!mounted) return;
      showAppErrorToast(context, message: error.toString());
      unawaited(_loadBuckets());
    }
  }
}
