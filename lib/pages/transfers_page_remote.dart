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
                  for (var index = 0; index < section.tasks.length; index++)
                    RemoteTaskRow(
                      task: section.tasks[index],
                      selected: _selectedTaskIds.contains(
                        section.tasks[index].id,
                      ),
                      onToggleSelected: () =>
                          _toggleTaskSelection(section.tasks[index].id),
                      onCancel: section.tasks[index].cancelable
                          ? () => _cancelRemoteTask(store, section.tasks[index])
                          : null,
                      onRetry: section.tasks[index].retryable
                          ? () => _retryRemoteTask(store, section.tasks[index])
                          : null,
                      onTrigger: section.tasks[index].triggerable
                          ? () =>
                                _triggerRemoteTask(store, section.tasks[index])
                          : null,
                      onExpanded: (expanded) {
                        if (expanded) {
                          unawaited(store.loadDetails(section.tasks[index].id));
                        }
                      },
                      showDivider: true,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  List<RemoteTask> _filteredRemoteTasks(RemoteTaskStore store) {
    return store.tasks
        .where((task) {
          if (!_remoteStatusFilter.matches(task) ||
              !_remoteKindFilter.matches(task)) {
            return false;
          }
          if (_searchText.isEmpty) return true;
          final text = <String>[
            task.name,
            task.sourcePath,
            task.targetPath,
            task.bucket,
            task.profileName,
            task.profileId,
          ].join('\n').toLowerCase();
          return text.contains(_searchText);
        })
        .toList(growable: false);
  }
  void _toggleRemoteVisibleSelection(List<RemoteTask> tasks) {
    final shouldSelect = tasks.any(
      (task) => !_selectedTaskIds.contains(task.id),
    );
    _remoteSetState(() {
      if (shouldSelect) {
        _selectedTaskIds.addAll(tasks.map((task) => task.id));
      } else {
        _selectedTaskIds.removeAll(tasks.map((task) => task.id));
      }
    });
  }
  Future<void> _cancelRemoteTask(RemoteTaskStore store, RemoteTask task) async {
    try {
      await store.cancel(task.id);
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, title: '取消失败', message: error.toString());
      }
    }
  }
  Future<void> _retryRemoteTask(RemoteTaskStore store, RemoteTask task) async {
    try {
      if (await store.retry(task.id) && mounted) {
        showAppToast(context, title: '已重试', message: task.name);
      }
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, title: '重试失败', message: error.toString());
      }
    }
  }
  Future<void> _triggerRemoteTask(
    RemoteTaskStore store,
    RemoteTask task,
  ) async {
    try {
      if (await store.trigger(task.id) && mounted) {
        showAppToast(context, title: '已开始', message: task.name);
      }
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, title: '启动失败', message: error.toString());
      }
    }
  }
  Future<void> _cancelSelectedRemote(
    RemoteTaskStore store,
    List<RemoteTask> selected,
  ) async {
    if (_runningBatchAction) return;
    _remoteSetState(() => _runningBatchAction = true);
    try {
      final results = await Future.wait(
        selected
            .where((task) => task.cancelable)
            .map((task) => store.cancel(task.id)),
      );
      final count = results.where((result) => result).length;
      if (mounted) showAppToast(context, title: '已请求取消', message: '$count 个任务');
    } finally {
      _remoteSetState(() => _runningBatchAction = false);
    }
  }
  Future<void> _triggerSelectedRemote(
    RemoteTaskStore store,
    List<RemoteTask> selected,
  ) async {
    if (_runningBatchAction) return;
    _remoteSetState(() => _runningBatchAction = true);
    try {
      final results = await Future.wait(
        selected
            .where((task) => task.triggerable)
            .map((task) => store.trigger(task.id)),
      );
      final count = results.where((result) => result).length;
      if (mounted) showAppToast(context, title: '已开始', message: '$count 个任务');
    } finally {
      _remoteSetState(() => _runningBatchAction = false);
    }
  }
  Future<void> _clearRemoteHistory(RemoteTaskStore store) async {
    if (_runningBatchAction) return;
    _remoteSetState(() => _runningBatchAction = true);
    try {
      final removed = await store.clearHistory();
      if (mounted) {
        showAppToast(context, title: '已清理历史', message: '$removed 条记录');
      }
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, title: '清理失败', message: error.toString());
      }
    } finally {
      _remoteSetState(() => _runningBatchAction = false);
    }
  }
  Widget _remoteDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T value) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    const width = 140.0;
    return SizedBox(
      width: width,
      child: ShadSelect<T>(
        key: ValueKey<Object>(value as Object),
        minWidth: width,
        initialValue: value,
        placeholder: Text(labelBuilder(value)),
        selectedOptionBuilder: (context, selected) =>
            Text(labelBuilder(selected)),
        options: items
            .map(
              (item) =>
                  ShadOption<T>(value: item, child: Text(labelBuilder(item))),
            )
            .toList(growable: false),
        onChanged: onChanged,
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
