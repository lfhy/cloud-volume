part of 'transfers_page.dart';

// Android 手机窄屏的紧凑头部：隐藏队列标签行与列表头（状态下拉已覆盖
// 同样筛选，列表与搜索框紧贴），页面级动作收进右上角入口的底部抽屉，
// 行级/批量动作在每行 `…` 抽屉里。桌面端保持完整队列头部不变。
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
    // 向 shell 报告选中态(两态模型):当前可见选择非空时底部导航栏让位
    // 给选中态动作条(由 transfers_page.dart 的全宽槽渲染)。报告仅在值
    // 变化时经微任务通知,可安全地在 build 里调用。
    MobileSelectionActivity.instance.report(
      SidebarItem.transfers,
      _androidCompactQueueHeader && selectedVisible > 0,
    );
    // Android 对齐文件管理基线:页面级动作(立即同步/清理全部历史)收进
    // 右上角单一 48dp 入口打开的共享底部抽屉,选中态不隐藏(行级/批量
    // 动作在每行 `…` 抽屉里);批处理运行中入口图标变 spinner,没有
    // 可用动作时入口整体隐藏。桌面保持内联按钮。
    Widget? androidActionsEntry;
    if (_androidCompactQueueHeader) {
      final sheetActions = _runningBatchAction
          ? const <MobilePageAction>[]
          : <MobilePageAction>[
              if (syncable > 0)
                MobilePageAction(
                  label: '立即同步 $syncable',
                  icon: LucideIcons.play,
                  onPressed: () => unawaited(_triggerAllRemoteTasks(store)),
                ),
              if (historyTotal > 0)
                MobilePageAction(
                  label: '清理全部历史 $historyTotal',
                  icon: LucideIcons.trash2,
                  onPressed: () => unawaited(_clearRemoteHistory(store)),
                ),
            ];
      if (_runningBatchAction || sheetActions.isNotEmpty) {
        androidActionsEntry = Semantics(
          label: '任务操作',
          child: ShadIconButton.ghost(
            width: 48,
            height: 48,
            iconSize: 22,
            icon: _runningBatchAction
                ? const AppLoadingIndicator(size: 22, strokeWidth: 2.4)
                : Icon(
                    LucideIcons.ellipsisVertical,
                    color: theme.colorScheme.primary,
                  ),
            onPressed: _runningBatchAction || sheetActions.isEmpty
                ? null
                : () => unawaited(
                    showMobileActionSheet(
                      context,
                      title: '任务操作',
                      actions: sheetActions,
                    ),
                  ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Android 两态选择模型:选中态头部变形为 取消/已选中 N 个任务/
        // 全选,批量动作在底部动作条;浏览态保持大标题 + 右上角页面动作
        // 入口。桌面保持完整队列头部不变。
        if (_androidCompactQueueHeader && selectedVisible > 0)
          MobileSelectionHeader(
            count: selectedVisible,
            noun: '任务',
            allSelected:
                visible.isNotEmpty &&
                visible.every((task) => _selectedTaskIds.contains(task.id)),
            onCancel: () => _remoteSetState(_selectedTaskIds.clear),
            onToggleSelectAll: () => _toggleRemoteVisibleSelection(visible),
          )
        else
          Row(
            crossAxisAlignment: _androidCompactQueueHeader
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              // 桌面端保持上游行为：标题始终显示、22 号、无副标题。Android
              // 按移动基线显示 23 号标题 + 副标题，选中态头部整体变形——
              // 计数与批量动作由选中态头部/底部动作条承载。
              Expanded(
                child: _androidCompactQueueHeader
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
                      ),
              ),
              if (androidActionsEntry != null) ...[
                const SizedBox(width: 8),
                androidActionsEntry,
              ],
            // 桌面端保持完整队列头部：内联 outline 按钮与原间距不变。
            if (!_androidCompactQueueHeader) ...[
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
          ],
        ),
        // 头部后间距对齐文件管理移动呈现(14dp),桌面保持 16。
        SizedBox(height: _androidCompactQueueHeader ? 14 : 16),
        // Android 窄屏不显示队列标签行：状态下拉已提供同样的筛选能力，
        // 这一行只会占用竖向空间。
        if (!_androidCompactQueueHeader) ...[
          _buildRemoteQueueTabs(theme, store),
          const SizedBox(height: 12),
        ],
        _buildRemoteFilters(),
        // 与文件管理页一致:搜索框与列表紧贴(12dp)。
        SizedBox(height: _androidCompactQueueHeader ? 12 : 16),
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
