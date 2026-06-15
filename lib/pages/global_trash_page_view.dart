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

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '回收站',
                      style: theme.textTheme.h3.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '集中管理已删除的文件与目录。',
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              GlobalTrashHeaderActions(
                selectedCount: selectedFilteredCount,
                loading: _loading,
                onRefresh: () => unawaited(_loadInitialBucket()),
                onRestoreSelected: () => unawaited(_restoreSelected()),
                onDeleteSelected: () => unawaited(_deleteSelected()),
                onClearTrash:
                    _activeBucket == null || _entries.isEmpty || _loading
                    ? null
                    : () => unawaited(_clearActiveBucketTrash()),
                onClearSelection: () => setState(() => _selectedIds.clear()),
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
      ),
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
      final text = _entries.isEmpty ? '当前存储桶回收站为空' : '当前搜索没有结果';
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
      showBucketColumn: false,
      onToggleSelection: _toggleSelection,
      onToggleSelectAll: _toggleSelectAllFiltered,
      onRestore: (entry) => unawaited(_restoreEntry(entry)),
      onDeletePermanently: (entry) => unawaited(_deleteEntry(entry)),
    );
  }
}
