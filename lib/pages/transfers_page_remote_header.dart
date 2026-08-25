part of 'transfers_page.dart';

// Queue-level controls act on all durable pending work, independent of row selection.
extension _TransfersPageRemoteHeader on _TransfersPageState {
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
    final clearable = selected.where(isRemoteTaskHistory).length;
    final syncable = store.tasks.where(_canBulkSyncRemoteTask).length;
    final historyTotal = store.queue.reported
        ? store.queue.history
        : store.tasks.where(isRemoteTaskHistory).length;
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
            const SizedBox(width: 10),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: _runningBatchAction || syncable == 0
                  ? null
                  : () => unawaited(_triggerAllRemoteTasks(store)),
              child: _batchActionButtonChild(
                _batchAction == _RemoteBatchAction.sync,
                syncable == 0 ? '立即同步' : '立即同步 $syncable',
                loadingLabel: '正在同步…',
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
                  child: _batchActionButtonChild(
                    _batchAction == _RemoteBatchAction.clearSelectedHistory,
                    '清理历史 $clearable',
                  ),
                ),
              ],
            ],
            if (historyTotal > 0) ...[
              const SizedBox(width: 10),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: _runningBatchAction
                    ? null
                    : () => unawaited(_clearRemoteHistory(store)),
                child: _batchActionButtonChild(
                  _batchAction == _RemoteBatchAction.clearAllHistory,
                  '清理全部历史 $historyTotal',
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _buildRemoteQueueTabs(theme, store),
        const SizedBox(height: 12),
        _buildRemoteFilters(),
        const SizedBox(height: 16),
        Expanded(
          child: _buildRemoteList(theme, store, visible, selectedVisible),
        ),
      ],
    );
  }
}

// Bulk sync also makes retry-wait work due now; row-level triggerability only
// describes the narrower single-task control and therefore is not sufficient.
bool _canBulkSyncRemoteTask(RemoteTask task) =>
    task.source == RemoteTaskSource.metadata &&
    switch (task.status) {
      RemoteTaskStatus.waiting ||
      RemoteTaskStatus.blocked ||
      RemoteTaskStatus.retryWait => true,
      _ => false,
    };
