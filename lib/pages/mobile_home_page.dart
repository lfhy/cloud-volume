// 移动端首页:问候与账号概览、任务状态卡、快捷入口(含设置——底栏
// 默认不显示设置,首页是它的保底入口)与最近任务动态。数据全部来自
// 已绑定的 RemoteTaskStore 与 BootstrapState,不在首页发起额外请求。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/sidebar_item.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/widgets/remote_task_style_helpers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class MobileHomePage extends StatelessWidget {
  const MobileHomePage({
    super.key,
    required this.state,
    required this.onNavigate,
  });

  final BootstrapState state;
  final ValueChanged<SidebarItem> onNavigate;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return '夜深了';
    if (hour < 11) return '早上好';
    if (hour < 13) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          '$_greeting，欢迎回来',
          style: theme.textTheme.h3.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          state.profiles.isEmpty
              ? '云卷 · 远程存储'
              : '云卷 · ${state.profiles.length} 个账号',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 18),
        _TaskOverviewCard(onNavigate: onNavigate),
        const SizedBox(height: 18),
        _QuickEntries(onNavigate: onNavigate),
        const SizedBox(height: 18),
        _RecentTasks(onNavigate: onNavigate),
      ],
    );
  }
}

/// 任务状态概览卡:进行中数量 + 聚合速度,点击进入任务队列。
class _TaskOverviewCard extends StatelessWidget {
  const _TaskOverviewCard({required this.onNavigate});

  final ValueChanged<SidebarItem> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ListenableBuilder(
      listenable: RemoteTaskStore.instance,
      builder: (context, _) {
        final store = RemoteTaskStore.instance;
        final active = store.tasks.where((t) => t.status.isActive).length;
        final speed = remoteTaskSpeedSummary(store.tasks);
        return _HomeCard(
          onTap: () => onNavigate(SidebarItem.transfers),
          child: Row(
            children: [
              Icon(
                LucideIcons.arrowLeftRight,
                size: 18,
                color: active > 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active > 0 ? '$active 个任务进行中' : '暂无进行中任务',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: active > 0
                            ? theme.colorScheme.primary
                            : theme.colorScheme.foreground,
                      ),
                    ),
                    if (speed.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        speed,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 快捷入口 2×2:文件管理、账号管理、回收站、系统设置(设置的保底入口)。
class _QuickEntries extends StatelessWidget {
  const _QuickEntries({required this.onNavigate});

  final ValueChanged<SidebarItem> onNavigate;

  static const List<SidebarItem> _entries = [
    SidebarItem.fileManager,
    SidebarItem.storage,
    SidebarItem.trash,
    SidebarItem.settings,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row < 2; row++) ...[
          Row(
            children: [
              for (final item in _entries.sublist(row * 2, row * 2 + 2)) ...[
                Expanded(child: _QuickEntryCard(item: item, onNavigate: onNavigate)),
                if (item != _entries[row * 2 + 1]) const SizedBox(width: 10),
              ],
            ],
          ),
          if (row == 0) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _QuickEntryCard extends StatelessWidget {
  const _QuickEntryCard({required this.item, required this.onNavigate});

  final SidebarItem item;
  final ValueChanged<SidebarItem> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return _HomeCard(
      onTap: () => onNavigate(item),
      child: Column(
        children: [
          Icon(
            item.icon,
            size: 22,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            item.desktopLabel,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// 最近任务动态:最新 3 条,点击进入任务队列查看全部。
class _RecentTasks extends StatelessWidget {
  const _RecentTasks({required this.onNavigate});

  final ValueChanged<SidebarItem> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ListenableBuilder(
      listenable: RemoteTaskStore.instance,
      builder: (context, _) {
        final tasks = RemoteTaskStore.instance.tasks.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '最近任务',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ),
            _HomeCard(
              onTap: tasks.isEmpty ? null : () => onNavigate(SidebarItem.transfers),
              child: tasks.isEmpty
                  ? Text(
                      '暂无任务记录',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < tasks.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: theme.colorScheme.border
                                  .withValues(alpha: 0.5),
                            ),
                          _RecentTaskRow(task: tasks[i]),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentTaskRow extends StatelessWidget {
  const _RecentTaskRow({required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final active = task.status.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              remoteTaskEntryName(task),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            remoteTaskStatusLabel(task),
            style: TextStyle(
              fontSize: 11.5,
              color: active
                  ? theme.colorScheme.primary
                  : remoteTaskStatusColor(theme, task.status),
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页统一卡片容器:主题背景之上的卡面 + 边框 + 圆角。
class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.border.withValues(alpha: 0.7)),
        ),
        child: child,
      ),
    );
  }
}
