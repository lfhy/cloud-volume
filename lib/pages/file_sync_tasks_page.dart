// 文件同步任务页：同步配置的唯一管理入口；进行中的同步项在每条配置卡片内摘要展示，完整列表见「传输」。
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/sync_profile_notifier.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/widgets/file_sync_profile_active_task.dart';
import 'package:remote_storage/services/sync_directory_navigation.dart';
import 'package:remote_storage/widgets/sync_directory_open_buttons.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/services/sync_editor_window_service.dart';
import 'package:remote_storage/widgets/file_sync_profile_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/services/app_modal.dart';

part 'file_sync_tasks_page_actions.dart';

class FileSyncTasksPage extends StatefulWidget {
  const FileSyncTasksPage({
    super.key,
    required this.api,
    required this.config,
    required this.profiles,
    this.active = false,
  });

  final RemoteStorageGateway api;
  final dynamic config;

  /// 已配置的账号列表，供加载各账号下的桶列表。
  final List<ProfileInfo> profiles;
  final bool active;

  @override
  State<FileSyncTasksPage> createState() => _FileSyncTasksPageState();
}

class _FileSyncTasksPageState extends State<FileSyncTasksPage> {
  List<FileManagerBucketEntry> _buckets = const [];
  bool _loadingBuckets = false;

  @override
  void initState() {
    super.initState();
    RemoteTaskStore.instance.addListener(_onQueueChanged);
    SyncProfileNotifier.instance.addListener(_onProfilesChanged);
    _loadBuckets();
  }

  @override
  void dispose() {
    RemoteTaskStore.instance.removeListener(_onQueueChanged);
    SyncProfileNotifier.instance.removeListener(_onProfilesChanged);
    super.dispose();
  }

  /// 供 actions part 文件触发重建。
  void markDirty(VoidCallback fn) => setState(fn);

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  void _onProfilesChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final profiles = SyncProfileNotifier.instance.profiles;
    final remoteTasks = RemoteTaskStore.instance.tasks;

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行：页面名称与新建配置按钮并排，让创建入口始终可见。
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '文件同步任务',
                    style: theme.textTheme.h3.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ShadButton(
                  onPressed: _loadingBuckets ? null : _addProfile,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.plus, size: 16),
                      SizedBox(width: 4),
                      Text('新建配置'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _summaryCards(theme, profiles, remoteTasks),
            const SizedBox(height: 24),
            Text(
              '同步配置',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.foreground,
              ),
            ),
            const SizedBox(height: 12),
            if (profiles.isEmpty)
              _emptyHint(theme, '还没有同步配置，点击右上角「新建配置」开始。')
            else
              ...profiles.map((p) => _profileRow(theme, p, remoteTasks)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCards(
    ShadThemeData theme,
    List<SyncProfileRuntime> profiles,
    List<RemoteTask> remoteTasks,
  ) {
    final enabled = profiles.where((p) => p.profile.enabled).length;
    final syncing = profiles
        .where((p) => p.status == SyncProfileStatus.syncing)
        .length;
    final profileIds = profiles.map((runtime) => runtime.profile.id).toSet();
    final syncTasks = remoteTasks.where(
      (task) =>
          task.source == RemoteTaskSource.sync &&
          profileIds.contains(task.profileId),
    );
    final running = syncTasks.where((task) => task.status.isActive).length;
    final failed = syncTasks
        .where(
          (task) =>
              task.status == RemoteTaskStatus.failed ||
              task.status == RemoteTaskStatus.conflict,
        )
        .length;
    return Row(
      children: [
        _statCard(theme, LucideIcons.refreshCw, '$enabled', '已启用配置'),
        const SizedBox(width: 12),
        _statCard(theme, LucideIcons.loader, '$syncing', '同步中'),
        const SizedBox(width: 12),
        _statCard(theme, LucideIcons.arrowDownUp, '$running', '执行中任务'),
        const SizedBox(width: 12),
        _statCard(theme, LucideIcons.alertCircle, '$failed', '失败任务'),
      ],
    );
  }

  Widget _statCard(
    ShadThemeData theme,
    IconData icon,
    String value,
    String label,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单条配置行：展示名称、状态、方向、待处理数和上次同步时间。
  /// 操作区提供立即同步、编辑、删除、启停开关，逻辑在 part 文件中。
  Widget _profileRow(
    ShadThemeData theme,
    SyncProfileRuntime runtime,
    List<RemoteTask> remoteTasks,
  ) {
    final remoteActive = latestActiveRemoteTaskForProfile(
      remoteTasks,
      runtime.profile.id,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  runtime.profile.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ),
              _statusBadge(theme, runtime.status),
            ],
          ),
          const SizedBox(height: 8),
          _metaRow(theme, LucideIcons.folder, runtime.profile.localPath),
          const SizedBox(height: 4),
          _metaRow(
            theme,
            LucideIcons.cloudUpload,
            '${runtime.profile.bucket}/${runtime.profile.remotePrefix.isEmpty ? '' : runtime.profile.remotePrefix}',
          ),
          const SizedBox(height: 4),
          _metaRow(
            theme,
            LucideIcons.arrowLeftRight,
            runtime.profile.direction.label,
          ),
          if (runtime.lastSyncAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            _metaRow(theme, LucideIcons.clock, '上次同步：${runtime.lastSyncAt}'),
          ],
          if (runtime.lastError.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              runtime.lastError,
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.destructive,
              ),
            ),
          ],
          if (remoteActive case final active?)
            FileSyncProfileRemoteTaskLine(task: active),
          const SizedBox(height: 12),
          Row(
            children: [
              ShadSwitch(
                value: runtime.profile.enabled,
                onChanged: (v) => _toggleEnabled(runtime, v),
              ),
              const SizedBox(width: 4),
              Text(
                runtime.profile.enabled ? '已启用' : '已暂停',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(width: 8),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: runtime.profile.localPath.trim().isEmpty
                    ? null
                    : () => SyncDirectoryOpenButtons.openLocal(
                        context,
                        runtime.profile.localPath.trim(),
                      ),
                child: const Text('打开本地目录'),
              ),
              const SizedBox(width: 6),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: () => SyncDirectoryNavigation.instance.openRemote(
                  runtime.profile.remoteOpenRequest,
                ),
                child: const Text('打开同步目录'),
              ),
              const Spacer(),
              ShadButton.outline(
                onPressed: () => _triggerSync(runtime),
                child: const Text('立即同步'),
              ),
              const SizedBox(width: 8),
              ShadButton.outline(
                onPressed: () => _editProfile(runtime),
                child: const Text('编辑'),
              ),
              const SizedBox(width: 8),
              ShadButton.destructive(
                onPressed: () => _deleteProfile(runtime),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaRow(ShadThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.mutedForeground),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(ShadThemeData theme, SyncProfileStatus status) {
    final (color, _) = _statusColor(theme, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  (Color, bool) _statusColor(ShadThemeData theme, SyncProfileStatus status) {
    switch (status) {
      case SyncProfileStatus.syncing:
        return (theme.colorScheme.primary, true);
      case SyncProfileStatus.error:
        return (theme.colorScheme.destructive, false);
      case SyncProfileStatus.paused:
        return (theme.colorScheme.mutedForeground, false);
      case SyncProfileStatus.idle:
        return (theme.colorScheme.primary, false);
    }
  }

  Widget _emptyHint(ShadThemeData theme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }
}
