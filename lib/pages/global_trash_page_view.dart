// ignore_for_file: invalid_use_of_protected_member

part of 'global_trash_page.dart';

// 全局回收站视图：将筛选和主体构建拆出，避免主页面文件继续膨胀。

extension _GlobalTrashPageView on _GlobalTrashPageState {
  List<GlobalTrashBrowserEntry> get _filteredEntries {
    if (_searchText.isEmpty) {
      return _entries;
    }
    return _entries
        .where((entry) {
          final haystack = <String>[
            entry.item.name,
            entry.item.originalKey,
          ].join('\n').toLowerCase();
          return haystack.contains(_searchText);
        })
        .toList(growable: false);
  }

  int get _selectedFilteredCount {
    return _filteredEntries
        .where((entry) => _selectedIds.contains(entry.id))
        .length;
  }

  Widget buildPage(BuildContext context) {
    final theme = ShadTheme.of(context);
    final filteredEntries = _filteredEntries;
    final selectedFilteredCount = _selectedFilteredCount;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 桌面端保持上游行为：标题始终显示。Android 窄屏在选中条目后
            // 把标题槽换成「已选 N 项」单行，而不是整块消失——标题位置
            // 仍然稳定，当前位置语义不丢。
            Expanded(
              child: isAndroid && _selectedIds.isNotEmpty
                  ? Text(
                      '已选 $selectedFilteredCount 项',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.h3.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '回收站',
                          style: theme.textTheme.h3.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: isAndroid ? 23 : 22,
                          ),
                        ),
                        if (isAndroid) ...[
                          const SizedBox(height: 3),
                          Text(
                            '浏览与恢复已删除的远端文件。',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.mutedForeground,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(width: 16),
            // 操作区按内容宽度布局，上限 360px（与 PageHeaderActions 阈值相等）。
            // Expanded 标题吃掉剩余空间，操作区贴右；窄窗口时操作区拿到的宽度
            // < 360，内层 LayoutBuilder 触发折叠成「…」菜单。
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: GlobalTrashHeaderActions(
                selectedCount: selectedFilteredCount,
                loading: _loading,
                onRefresh: () => unawaited(_loadInitialBucket()),
                onRestoreSelected: () => unawaited(_restoreSelected()),
                onDeleteSelected: () => unawaited(_deleteSelected()),
                onClearTrash:
                    _activeBucket == null || _entries.isEmpty || _loading
                    ? null
                    : () => unawaited(_clearActiveBucketTrash()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GlobalTrashFilters(
          searchController: _searchController,
          bucketFilter: _activeBucket ?? '',
          bucketOptions: _bucketOptions,
          onBucketChanged: (value) {
            if (value == null || value.isEmpty) {
              return;
            }
            unawaited(_switchBucket(value));
          },
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildBody(theme, filteredEntries)),
      ],
    );

    if (isAndroid) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: page,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: page,
    );
  }

  Widget _buildBody(
    ShadThemeData theme,
    List<GlobalTrashBrowserEntry> filteredEntries,
  ) {
    if (_loading) {
      return const Center(
        child: AppLoadingIndicator(size: 22, strokeWidth: 2.4),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 40,
              color: theme.colorScheme.destructive,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    if (_activeBucket == null) {
      return Center(
        child: Text(
          '暂无可用存储桶',
          style: TextStyle(color: theme.colorScheme.mutedForeground),
        ),
      );
    }
    if (filteredEntries.isEmpty) {
      final text = _entries.isEmpty
          ? '${_activeBucketLabel ?? '当前存储桶'}回收站为空'
          : '当前搜索没有结果';
      return Center(
        child: Text(
          text,
          style: TextStyle(color: theme.colorScheme.mutedForeground),
        ),
      );
    }
    return GlobalTrashBrowser(
      entries: filteredEntries,
      scrollController: _scrollController,
      loadingMore: _loadingMore,
      selectedIds: _selectedIds,
      busyIds: _busyEntries,
      // With multi-account aggregation the bucket id is `profile::bucket`,
      // which is not useful to display as a raw column. Hide the per-entry
      // bucket column in the global trash page (the bucket filter dropdown
      // above already lets users switch buckets).
      showBucketColumn: false,
      onToggleSelection: _toggleSelection,
      onToggleSelectAll: _toggleSelectAllFiltered,
      onRestore: (entry) => unawaited(_restoreEntry(entry)),
      onDeletePermanently: (entry) => unawaited(_deleteEntry(entry)),
    );
  }
}
