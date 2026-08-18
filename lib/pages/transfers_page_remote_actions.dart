part of 'transfers_page.dart';

// Task actions and filters stay separate from the list layout so the page
// remains a small projection view rather than a second queue implementation.
extension _TransfersPageRemoteActions on _TransfersPageState {
  List<RemoteTask> _filteredRemoteTasks(RemoteTaskStore store) => store.tasks
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
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, title: '批量取消失败', message: error.toString());
      }
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
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, title: '批量启动失败', message: error.toString());
      }
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

  Future<void> _clearSelectedRemoteHistory(
    RemoteTaskStore store,
    List<RemoteTask> selected,
  ) async {
    if (_runningBatchAction) return;
    final taskIds = selected
        .where((task) => !task.status.isActive)
        .map((task) => task.id)
        .toList(growable: false);
    if (taskIds.isEmpty) return;
    _remoteSetState(() => _runningBatchAction = true);
    try {
      final removed = await store.clearHistory(taskIds: taskIds);
      if (mounted) {
        _selectedTaskIds.removeAll(taskIds);
        showAppToast(context, title: '已清理历史', message: '$removed 条记录');
        _remoteSetState(() {});
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
