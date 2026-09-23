part of 'transfers_page.dart';

// Android 选中态底部动作条的动作装配(两态选择模型):选中 1 个时为该任务
// 自身可用动作,多个时为当前选择的批量动作。标签保持短动词(计数由
// MobileSelectionHeader 的「已选中 N 个任务」表达)。拆出以守住
// transfers_page_remote.dart 的 500 行上限。

extension _TransfersPageRemoteOverflow on _TransfersPageState {
  /// Android 选中态底部动作条;批处理运行中返回空(动作条显示 busy)。
  List<MobilePageAction> _mobileSelectionBarActions(
    RemoteTaskStore store,
    List<RemoteTask> visible,
  ) {
    if (_runningBatchAction) {
      return const <MobilePageAction>[];
    }
    final selected = visible
        .where((item) => _selectedTaskIds.contains(item.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      return const <MobilePageAction>[];
    }
    if (selected.length == 1) {
      final task = selected.single;
      return <MobilePageAction>[
        // 详情(任务详情 sheet)是首项:展示行级原本承载的摘要元信息
        // (操作/状态/桶/完整路径/阶段/依赖/错误);动态事件与传输 ID
        // 仍是桌面展开面板的内容。
        MobilePageAction(
          label: '详情',
          icon: LucideIcons.info,
          onPressed: () => unawaited(
            showMobileDetailSheet(
              context,
              title: '任务详情',
              rows: [
                MobileDetailRow('操作', remoteTaskKindLabel(task.kind)),
                MobileDetailRow('状态', remoteTaskStatusLabel(task)),
                if (task.bucket.trim().isNotEmpty)
                  MobileDetailRow('所属桶', task.bucket),
                if (task.operationPath.isNotEmpty)
                  MobileDetailRow('完整路径', task.operationPath),
                if (task.localPath.isNotEmpty)
                  MobileDetailRow('本地路径', task.localPath),
                if (task.mountReadRange.isNotEmpty)
                  MobileDetailRow('读取范围', task.mountReadRange)
                else if (task.phaseLabel.isNotEmpty)
                  MobileDetailRow('阶段', task.phaseLabel),
                if (task.blockedReason.isNotEmpty)
                  MobileDetailRow('依赖', remoteTaskBlockedReasonLabel(task)),
                if (task.error.isNotEmpty) MobileDetailRow('错误', task.error),
              ],
            ),
          ),
        ),
        if (task.triggerable)
          MobilePageAction(
            label: '立即执行',
            icon: LucideIcons.play,
            onPressed: () => unawaited(_triggerRemoteTask(store, task)),
          ),
        if (task.cancelable)
          MobilePageAction(
            label: '取消任务',
            icon: LucideIcons.circleX,
            onPressed: () => unawaited(_cancelRemoteTask(store, task)),
          ),
        if (task.retryable)
          MobilePageAction(
            label: '重试',
            icon: LucideIcons.refreshCw,
            onPressed: () => unawaited(_retryRemoteTask(store, task)),
          ),
        if (isRemoteTaskHistory(task))
          MobilePageAction(
            label: '清理历史',
            icon: LucideIcons.trash2,
            onPressed: () => unawaited(
              _clearSelectedRemoteHistory(store, selected),
            ),
          ),
      ];
    }
    final triggerable = selected.where((item) => item.triggerable).length;
    final cancelable = selected.where((item) => item.cancelable).length;
    final clearable = selected.where(isRemoteTaskHistory).length;
    return <MobilePageAction>[
      if (triggerable > 0)
        MobilePageAction(
          label: '立即执行',
          icon: LucideIcons.play,
          onPressed: () => unawaited(_triggerSelectedRemote(store, selected)),
        ),
      if (cancelable > 0)
        MobilePageAction(
          label: '取消任务',
          icon: LucideIcons.circleX,
          onPressed: () => unawaited(_cancelSelectedRemote(store, selected)),
        ),
      if (clearable > 0)
        MobilePageAction(
          label: '清理历史',
          icon: LucideIcons.trash2,
          onPressed: () => unawaited(
            _clearSelectedRemoteHistory(store, selected),
          ),
        ),
    ];
  }

  /// Android 选中态底部动作条的全宽槽(百度式贴底,自带底部安全区):单个
  /// 选择为该任务动作,多个为批量动作;批处理运行中整条变 spinner。动作
  /// 装配跟随任务 store 重建,选中态消失时返回空盒。
  Widget _buildAndroidSelectionBarSlot() {
    if (!_androidCompactQueueHeader) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: RemoteTaskStore.instance,
      builder: (context, _) {
        final store = RemoteTaskStore.instance;
        final visible = _filteredRemoteTasks(store);
        final selectedVisible = visible
            .where((task) => _selectedTaskIds.contains(task.id))
            .length;
        if (selectedVisible == 0) return const SizedBox.shrink();
        return MobileSelectionBottomBar(
          actions: _mobileSelectionBarActions(store, visible),
          busy: _runningBatchAction,
        );
      },
    );
  }

  // Queue-tab row switches the list between status queues; each tab is a
  // dedicated StatefulWidget per the hover binding rule.
  Widget _buildRemoteQueueTabs(ShadThemeData theme, RemoteTaskStore store) {
    final tasks = store.tasks;
    final serverQueue = store.queue;
    final hasServerCounts = serverQueue.reported;
    int count(_RemoteTaskStatusFilter filter) {
      // Prefer server-reported unpaged counts; loaded rows are only a
      // fallback for older binaries that omit the queue field.
      if (hasServerCounts) {
        return switch (filter) {
          _RemoteTaskStatusFilter.all => serverQueue.total,
          _RemoteTaskStatusFilter.active => serverQueue.active,
          _RemoteTaskStatusFilter.waiting => serverQueue.waiting,
          _RemoteTaskStatusFilter.failed => serverQueue.failed,
          _RemoteTaskStatusFilter.history => serverQueue.history,
        };
      }
      return tasks
          .where(
            (task) =>
                filter == _RemoteTaskStatusFilter.all || filter.matches(task),
          )
          .length;
    }

    return Row(
      children: [
        for (final filter in _RemoteTaskStatusFilter.values) ...[
          _RemoteQueueTab(
            label: filter.label,
            count: count(filter),
            selected: filter == _remoteStatusFilter,
            onTap: () => _remoteSetState(() => _remoteStatusFilter = filter),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}
