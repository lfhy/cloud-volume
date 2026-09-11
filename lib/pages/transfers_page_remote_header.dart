part of 'transfers_page.dart';

// Android 手机窄屏的紧凑头部：隐藏队列标签行（状态下拉已覆盖同样筛选），
// 并在选中任务时隐藏队列级按钮、只保留选中级操作，避免按钮行超宽被裁切。
// 桌面端保持完整队列头部不变。
bool get _androidCompactQueueHeader =>
    defaultTargetPlatform == TargetPlatform.android;

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
          crossAxisAlignment: _androidCompactQueueHeader
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            // 桌面端保持上游行为：标题始终显示、22 号、无副标题。Android
            // 窄屏在选中任务后把标题槽换成「已选 N 项」，为批量操作按钮
            // 腾出宽度；无选中时按移动基线显示 23 号标题 + 副标题。
            Expanded(
              child: _selectedTaskIds.isEmpty || !_androidCompactQueueHeader
                  ? _androidCompactQueueHeader
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '任务队列',
                                style: theme.textTheme.h3.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 23,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '查看传输与同步任务的进度。',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.mutedForeground,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            '任务队列',
                            style: theme.textTheme.h3.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                          )
                  : Text(
                      '已选 ${_selectedTaskIds.length} 项',
                      style: theme.textTheme.h3.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            // Android 窄屏：选中任务后隐藏队列级按钮，只保留选中级操作，
            // 避免一行按钮超出屏幕宽度被裁切；按钮在 Android 保持 48dp
            // 触控高，桌面维持 sm 原高。
            if (!_androidCompactQueueHeader || _selectedTaskIds.isEmpty)
              _queueActionButton(
                height: _androidCompactQueueHeader ? 48 : null,
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
              // Android 窄屏：立即执行/取消在每行的小图标里已有，选中后
              // 头部只保留「清理历史」，避免按钮行超出屏幕宽度。
              if (!_androidCompactQueueHeader) ...[
                const SizedBox(width: 10),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _runningBatchAction || triggerable == 0
                      ? null
                      : () =>
                            unawaited(_triggerSelectedRemote(store, selected)),
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
              if (clearable > 0) ...[
                const SizedBox(width: 6),
                _queueActionButton(
                  height: _androidCompactQueueHeader ? 48 : null,
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
            if (historyTotal > 0 &&
                (!_androidCompactQueueHeader || _selectedTaskIds.isEmpty)) ...[
              const SizedBox(width: 10),
              _queueActionButton(
                height: _androidCompactQueueHeader ? 48 : null,
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
        // Android 窄屏不显示队列标签行：状态下拉已提供同样的筛选能力，
        // 这一行只会占用竖向空间。
        if (!_androidCompactQueueHeader) ...[
          _buildRemoteQueueTabs(theme, store),
          const SizedBox(height: 12),
        ],
        _buildRemoteFilters(),
        const SizedBox(height: 16),
        Expanded(
          child: _buildRemoteList(theme, store, visible, selectedVisible),
        ),
      ],
    );
  }

  /// Queue-level outline button: Android keeps a 48dp touch height inside a
  /// centered hit box; desktop keeps the original sm sizing.
  Widget _queueActionButton({
    double? height,
    VoidCallback? onPressed,
    required Widget child,
  }) {
    final android = _androidCompactQueueHeader;
    final button = ShadButton.outline(
      size: ShadButtonSize.sm,
      height: height,
      onPressed: onPressed,
      child: child,
    );
    if (!android) return button;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Center(child: button),
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
