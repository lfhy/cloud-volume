// 账号管理列表提供和桶列表一致的卡片/表格双视图。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStorageAccountList extends StatelessWidget {
  static const double _typeColumnWidth = 104;
  static const double _statusColumnWidth = 92;
  static const double _actionColumnWidth = 212;

  const CloudStorageAccountList({
    super.key,
    required this.accounts,
    required this.isGrid,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final List<ProfileInfo> accounts;
  final bool isGrid;
  final bool busy;
  final ValueChanged<ProfileInfo> onEdit;
  final ValueChanged<ProfileInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (accounts.isEmpty) {
      return Center(
        child: Text(
          '还没有账号。',
          style: TextStyle(color: theme.colorScheme.mutedForeground),
        ),
      );
    }
    if (isGrid) return _buildGrid(context);
    return _buildTable(context);
  }

  Widget _buildGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 288).floor().clamp(2, 5);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisExtent: 154,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: accounts.length,
          itemBuilder: (context, index) {
            final profile = accounts[index];
            return _AccountCard(
              profile: profile,
              busy: busy,
              onEdit: onEdit,
              onDelete: onDelete,
            );
          },
        );
      },
    );
  }

  Widget _buildTable(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _AccountTableHeader(theme: theme),
          Expanded(
            child: ListView.builder(
              itemCount: accounts.length,
              itemBuilder: (context, index) {
                final profile = accounts[index];
                return FileListTile(
                  leading: _AccountIcon(profile: profile),
                  title: _profileTitle(profile),
                  subtitleLabel: profile.endpoint,
                  sizeLabel: _storageLabel(profile),
                  sizeColumnWidthOverride: _typeColumnWidth,
                  statusWidget: const _AccountStatus(),
                  trailing: _AccountActions(
                    profile: profile,
                    busy: busy,
                    onEdit: onEdit,
                    onDelete: onDelete,
                  ),
                  onTap: () {},
                  showDivider: index != accounts.length - 1,
                  deleting: busy,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _profileTitle(ProfileInfo profile) {
    return profile.displayName.isEmpty ? profile.name : profile.displayName;
  }

  static String _storageLabel(ProfileInfo profile) {
    return profile.storageType.label;
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.profile,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final ProfileInfo profile;
  final bool busy;
  final ValueChanged<ProfileInfo> onEdit;
  final ValueChanged<ProfileInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AccountIcon(profile: profile),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  CloudStorageAccountList._profileTitle(profile),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const _AccountStatus(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            CloudStorageAccountList._storageLabel(profile),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.mutedForeground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            profile.endpoint,
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.mutedForeground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _AccountActionButton(
                label: '编辑',
                icon: LucideIcons.pencil,
                onPressed: busy ? null : () => onEdit(profile),
              ),
              const SizedBox(width: 6),
              _AccountActionButton(
                label: '退出',
                icon: LucideIcons.logOut,
                destructive: true,
                onPressed: busy ? null : () => onDelete(profile),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountTableHeader extends StatelessWidget {
  const _AccountTableHeader({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final dividerColor = theme.colorScheme.border.withValues(alpha: 0.7);
    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.mutedForeground,
      letterSpacing: 0.2,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 0.6)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32),
          const SizedBox(width: 12),
          Expanded(child: Text('账号', style: labelStyle)),
          const SizedBox(width: 12),
          SizedBox(
            width: CloudStorageAccountList._typeColumnWidth,
            child: Text('类型', textAlign: TextAlign.right, style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: CloudStorageAccountList._statusColumnWidth,
            child: Text('状态', textAlign: TextAlign.right, style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: CloudStorageAccountList._actionColumnWidth,
            child: Text('操作', textAlign: TextAlign.right, style: labelStyle),
          ),
        ],
      ),
    );
  }
}

class _AccountActions extends StatelessWidget {
  const _AccountActions({
    required this.profile,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final ProfileInfo profile;
  final bool busy;
  final ValueChanged<ProfileInfo> onEdit;
  final ValueChanged<ProfileInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CloudStorageAccountList._actionColumnWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _AccountActionButton(
            label: '编辑',
            icon: LucideIcons.pencil,
            onPressed: busy ? null : () => onEdit(profile),
          ),
          const SizedBox(width: 6),
          _AccountActionButton(
            label: '退出',
            icon: LucideIcons.logOut,
            destructive: true,
            onPressed: busy ? null : () => onDelete(profile),
          ),
        ],
      ),
    );
  }
}

class _AccountActionButton extends StatelessWidget {
  const _AccountActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = destructive
        ? theme.colorScheme.destructive
        : theme.colorScheme.primary;
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, color: color)),
        ],
      ),
    );
  }
}

class _AccountStatus extends StatelessWidget {
  const _AccountStatus();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Text(
      '已保存',
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
  }
}

class _AccountIcon extends StatelessWidget {
  const _AccountIcon({required this.profile});

  final ProfileInfo profile;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox(
      width: 32,
      height: 32,
      child: Icon(
        profile.storageType == StorageType.webdav
            ? LucideIcons.server
            : LucideIcons.cloud,
        size: 18,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
