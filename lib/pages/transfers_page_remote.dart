part of 'transfers_page.dart';

// Unified task page renders backend-effective operations instead of raw snapshots.
extension _TransfersPageRemote on _TransfersPageState {
  Widget _buildRemoteQueueBody(ShadThemeData theme, RemoteTaskStore store) {
    final visible = _filteredRemoteTasks(store);
    final selectedVisible = visible
        .where((task) => _selectedTaskIds.contains(task.id))
        .length;
    final selected = visible
        .where((task) => _selectedTaskIds.contains(task.id))
        .toList(growable: false);
    final cancelable = selected.where((task) => task.cancelable).length;
    final triggerable = selected.where((task) => task.triggerable).length;
    final clearable = selected.where((task) => !task.status.isActive).length;
    final historyCount = store.tasks
        .where((task) => !task.status.isActive)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '任务队列',
                style: theme.textTheme.h3.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                ),
              ),
            ),
            if (_selectedTaskIds.isNotEmpty) ...[
              const SizedBox(width: 10),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: _runningBatchAction || triggerable == 0
                    ? null
                    : () => unawaited(_triggerSelectedRemote(store, selected)),
                child: Text(triggerable == 0 ? '立即执行' : '立即执行 $triggerable'),
              ),
              const SizedBox(width: 6),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: _runningBatchAction || cancelable == 0
                    ? null
                    : () => unawaited(_cancelSelectedRemote(store, selected)),
                child: Text(cancelable == 0 ? '取消' : '取消 $cancelable'),
              ),
              if (clearable > 0) ...[
                const SizedBox(width: 6),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _runningBatchAction
                      ? null
                      : () => unawaited(
                          _clearSelectedRemoteHistory(store, selected),
                        ),
                  child: Text('清理历史 $clearable'),
                ),
              ],
            ],
            if (_selectedTaskIds.isEmpty && historyCount > 0) ...[
              const SizedBox(width: 10),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: _runningBatchAction
                    ? null
                    : () => unawaited(_clearRemoteHistory(store)),
                child: const Text('清理历史'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _buildRemoteFilters(),
        const SizedBox(height: 16),
        Expanded(
          child: _buildRemoteList(theme, store, visible, selectedVisible),
        ),
      ],
    );
  }

  Widget _buildRemoteFilters() {
    return Row(
      children: [
        Expanded(
          child: ShadInput(
            controller: _searchController,
            placeholder: const Text('搜索操作、路径、存储桶或账号'),
          ),
        ),
        const SizedBox(width: 12),
        _remoteDropdown<_RemoteTaskStatusFilter>(
          value: _remoteStatusFilter,
          items: _RemoteTaskStatusFilter.values,
          labelBuilder: (value) => value.label,
          onChanged: (value) {
            if (value != null) {
              _remoteSetState(() => _remoteStatusFilter = value);
            }
          },
        ),
        const SizedBox(width: 12),
        _remoteDropdown<_RemoteTaskKindFilter>(
          value: _remoteKindFilter,
          items: _RemoteTaskKindFilter.values,
          labelBuilder: (value) => value.label,
          onChanged: (value) {
            if (value != null) {
              _remoteSetState(() => _remoteKindFilter = value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildRemoteList(
    ShadThemeData theme,
    RemoteTaskStore store,
    List<RemoteTask> visible,
    int selectedVisible,
  ) {
    if (store.lastError != null && store.tasks.isEmpty) {
      return _buildEmptyState(theme, '任务服务暂不可用', '统一远端任务列表暂时无法刷新，请稍后重试。');
    }
    if (store.tasks.isEmpty) {
      return _buildEmptyState(theme, '暂无任务', '本地修改和远端操作会在这里显示。');
    }
    if (visible.isEmpty) {
      return _buildEmptyState(theme, '没有匹配结果', '调整筛选条件后再试。');
    }
    final allSelected = visible.every(
      (task) => _selectedTaskIds.contains(task.id),
    );
    final partial = selectedVisible > 0 && !allSelected;
    final sections = _groupRemoteTasks(visible);
    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _RemoteListHeader(
            totalCount: visible.length,
            speedSummary: remoteTaskSpeedSummary(visible),
            allSelected: allSelected,
            partial: partial,
            onToggleAll: () => _toggleRemoteVisibleSelection(visible),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final section in sections) ...[
                  _RemoteSectionHeader(
                    label: section.label,
                    count: section.tasks.length,
                  ),
                  for (final task in section.tasks)
                    RemoteTaskRow(
                      key: ValueKey<String>(task.id),
                      task: task,
                      selected: _selectedTaskIds.contains(task.id),
                      onToggleSelected: () => _toggleTaskSelection(task.id),
                      onCancel: task.cancelable
                          ? () => _cancelRemoteTask(store, task)
                          : null,
                      onRetry: task.retryable
                          ? () => _retryRemoteTask(store, task)
                          : null,
                      onTrigger: task.triggerable
                          ? () => _triggerRemoteTask(store, task)
                          : null,
                      onExpanded: (expanded) {
                        if (expanded) {
                          unawaited(store.loadDetails(task.id));
                        }
                      },
                      showDivider: true,
                    ),
                  if (store.nextCursor.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: ShadButton.outline(
                        onPressed: store.isRefreshing
                            ? null
                            : () => unawaited(store.loadMore()),
                        child: Text(store.isRefreshing ? '正在加载...' : '加载更多历史'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteTaskSection {
  const _RemoteTaskSection(this.label, this.tasks);
  final String label;
  final List<RemoteTask> tasks;
}

List<_RemoteTaskSection> _groupRemoteTasks(List<RemoteTask> tasks) {
  final active = <RemoteTask>[];
  final waiting = <RemoteTask>[];
  final attention = <RemoteTask>[];
  final history = <RemoteTask>[];
  for (final task in tasks) {
    switch (task.status) {
      case RemoteTaskStatus.running:
      case RemoteTaskStatus.verifying:
      case RemoteTaskStatus.cancelRequested:
      case RemoteTaskStatus.reconciling:
        active.add(task);
      case RemoteTaskStatus.waiting:
      case RemoteTaskStatus.blocked:
      case RemoteTaskStatus.retryWait:
        waiting.add(task);
      case RemoteTaskStatus.failed:
      case RemoteTaskStatus.conflict:
        attention.add(task);
      case RemoteTaskStatus.done:
      case RemoteTaskStatus.canceled:
        history.add(task);
    }
  }
  return <_RemoteTaskSection>[
    if (active.isNotEmpty) _RemoteTaskSection('进行中', active),
    if (waiting.isNotEmpty) _RemoteTaskSection('等待中', waiting),
    if (attention.isNotEmpty) _RemoteTaskSection('需要处理', attention),
    if (history.isNotEmpty) _RemoteTaskSection('历史', history),
  ];
}

class _RemoteListHeader extends StatelessWidget {
  const _RemoteListHeader({
    required this.totalCount,
    required this.speedSummary,
    required this.allSelected,
    required this.partial,
    required this.onToggleAll,
  });
  final int totalCount;
  final String speedSummary;
  final bool allSelected;
  final bool partial;
  final VoidCallback onToggleAll;
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.border.withValues(alpha: 0.7),
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          ListSelectionControl(
            selected: allSelected,
            partiallySelected: partial,
            onTap: onToggleAll,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              allSelected ? '取消全选当前结果' : '全选当前结果',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '共 $totalCount 项',
            style: TextStyle(
              fontSize: 10.5,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          if (speedSummary.isNotEmpty) ...[
            const SizedBox(width: 16),
            Text(
              speedSummary,
              style: TextStyle(
                fontSize: 10.5,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoteSectionHeader extends StatelessWidget {
  const _RemoteSectionHeader({required this.label, required this.count});
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Text(
        '$label  $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }
}

enum _RemoteTaskStatusFilter {
  all('全部状态'),
  active('进行中'),
  waiting('等待中'),
  failed('失败/冲突'),
  history('历史');

  const _RemoteTaskStatusFilter(this.label);
  final String label;
  bool matches(RemoteTask task) => switch (this) {
    _RemoteTaskStatusFilter.all => true,
    _RemoteTaskStatusFilter.active =>
      task.status == RemoteTaskStatus.running ||
          task.status == RemoteTaskStatus.verifying ||
          task.status == RemoteTaskStatus.cancelRequested ||
          task.status == RemoteTaskStatus.reconciling,
    _RemoteTaskStatusFilter.waiting =>
      task.status == RemoteTaskStatus.waiting ||
          task.status == RemoteTaskStatus.blocked ||
          task.status == RemoteTaskStatus.retryWait,
    _RemoteTaskStatusFilter.failed =>
      task.status == RemoteTaskStatus.failed ||
          task.status == RemoteTaskStatus.conflict,
    _RemoteTaskStatusFilter.history =>
      task.status == RemoteTaskStatus.done ||
          task.status == RemoteTaskStatus.canceled,
  };
}

enum _RemoteTaskKindFilter {
  all('全部类型'),
  upload('上传/写入'),
  download('下载'),
  directory('创建目录'),
  move('重命名/移动'),
  delete('删除');

  const _RemoteTaskKindFilter(this.label);
  final String label;
  bool matches(RemoteTask task) => switch (this) {
    _RemoteTaskKindFilter.all => true,
    _RemoteTaskKindFilter.upload =>
      task.kind == RemoteTaskKind.upload || task.kind == RemoteTaskKind.write,
    _RemoteTaskKindFilter.download => task.kind == RemoteTaskKind.download,
    _RemoteTaskKindFilter.directory => task.kind == RemoteTaskKind.mkdir,
    _RemoteTaskKindFilter.move =>
      task.kind == RemoteTaskKind.rename || task.kind == RemoteTaskKind.move,
    _RemoteTaskKindFilter.delete => task.kind == RemoteTaskKind.delete,
  };
}
