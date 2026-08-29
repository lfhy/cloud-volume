// 账号管理列表提供和桶列表一致的卡片/表格双视图。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Connection-probe status for one account, shown in the account-management
/// status column. Defined here (next to the widget that renders it) and
/// re-exported so the page can populate it without a circular import.
enum AccountStatus { checking, ok, error, disabled }

class CloudStorageAccountList extends StatelessWidget {
  static const double _typeColumnWidth = 104;
  static const double _actionColumnWidth = 360;

  const CloudStorageAccountList({
    super.key,
    required this.accounts,
    required this.isGrid,
    this.mobileLayout = false,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onManageBuckets,
    required this.onToggleDisabled,
    required this.status,
    required this.statusError,
    this.onReorder,
  });

  final List<ProfileInfo> accounts;
  final bool isGrid;
  final bool mobileLayout;
  final bool busy;
  final ValueChanged<ProfileInfo> onEdit;
  final ValueChanged<ProfileInfo> onDelete;
  final ValueChanged<ProfileInfo> onManageBuckets;

  /// (profile, disabled) — disabled=true means the user turned the account OFF.
  final void Function(ProfileInfo profile, bool disabled) onToggleDisabled;

  /// Per-profile connection status (keyed by profile name) for the status column.
  final Map<String, AccountStatus> status;

  /// Optional human-readable error message for accounts in [AccountStatus.error].
  final Map<String, String> statusError;
  final void Function(int oldIndex, int newIndex)? onReorder;

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
    if (mobileLayout) return _buildMobileList(context);
    if (isGrid) return _buildGrid(context);
    return _buildTable(context);
  }

  Widget _buildMobileList(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: accounts.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final profile = accounts[index];
        return _AccountCard(
          profile: profile,
          busy: busy,
          onEdit: onEdit,
          onDelete: onDelete,
          onManageBuckets: onManageBuckets,
          onToggleDisabled: onToggleDisabled,
          status: status[profile.name] ?? AccountStatus.checking,
          statusError: statusError[profile.name],
          mobileLayout: true,
        );
      },
    );
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
              onManageBuckets: onManageBuckets,
              onToggleDisabled: onToggleDisabled,
              status: status[profile.name] ?? AccountStatus.checking,
              statusError: statusError[profile.name],
            );
          },
        );
      },
    );
  }

  Widget _buildTable(BuildContext context) {
    final theme = ShadTheme.of(context);
    final canReorder = onReorder != null && accounts.length > 1;
    return ShadCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _AccountTableHeader(theme: theme),
          Expanded(
            child: canReorder
                ? ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: accounts.length,
                    // Classic onReorder API keeps this building on Flutter
                    // 3.41; onReorderItem exists only on 3.47+.
                    onReorder: onReorder!,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        elevation: 1.5,
                        color: Colors.transparent,
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final profile = accounts[index];
                      return ReorderableDragStartListener(
                        key: ValueKey('account-${profile.name}'),
                        index: index,
                        child: _buildAccountRow(
                          profile: profile,
                          index: index,
                          showDragHandle: true,
                        ),
                      );
                    },
                  )
                : ListView.builder(
                    itemCount: accounts.length,
                    itemBuilder: (context, index) {
                      final profile = accounts[index];
                      return KeyedSubtree(
                        key: ValueKey('account-${profile.name}'),
                        child: _buildAccountRow(
                          profile: profile,
                          index: index,
                          showDragHandle: false,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow({
    required ProfileInfo profile,
    required int index,
    required bool showDragHandle,
  }) {
    return FileListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle) ...[
            const _ListDragHandle(),
            const SizedBox(width: 6),
          ],
          const _AccountIcon(),
        ],
      ),
      title: profile.disabled
          ? '${_profileTitle(profile)}（已禁用）'
          : _profileTitle(profile),
      subtitleLabel: profile.endpoint,
      sizeLabel: _storageLabel(profile),
      sizeColumnWidthOverride: _typeColumnWidth,
      trailing: _AccountActions(
        profile: profile,
        busy: busy,
        onEdit: onEdit,
        onDelete: onDelete,
        onManageBuckets: onManageBuckets,
        onToggleDisabled: onToggleDisabled,
        status: status[profile.name] ?? AccountStatus.checking,
        statusError: statusError[profile.name],
      ),
      onTap: () {},
      showDivider: index != accounts.length - 1,
      deleting: busy,
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
    required this.onManageBuckets,
    required this.onToggleDisabled,
    required this.status,
    required this.statusError,
    this.mobileLayout = false,
  });

  final ProfileInfo profile;
  final bool busy;
  final ValueChanged<ProfileInfo> onEdit;
  final ValueChanged<ProfileInfo> onDelete;
  final ValueChanged<ProfileInfo> onManageBuckets;
  final void Function(ProfileInfo profile, bool disabled) onToggleDisabled;
  final AccountStatus status;
  final String? statusError;
  final bool mobileLayout;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final title = profile.disabled
        ? '${CloudStorageAccountList._profileTitle(profile)}?????'
        : CloudStorageAccountList._profileTitle(profile);
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _AccountIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AccountStatusChip(status: status, error: statusError),
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
          const SizedBox(height: 12),
          if (mobileLayout)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ShadSwitch(
                      value: !profile.disabled,
                      onChanged: busy
                          ? null
                          : (enabled) => onToggleDisabled(profile, !enabled),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        profile.disabled ? 'Disabled' : 'Enabled',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AccountActionButton(
                        label: 'Buckets',
                        icon: LucideIcons.listFilter,
                        onPressed: busy ? null : () => onManageBuckets(profile),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AccountActionButton(
                        label: 'Edit',
                        icon: LucideIcons.pencil,
                        onPressed: busy ? null : () => onEdit(profile),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AccountActionButton(
                        label: 'Remove',
                        icon: LucideIcons.logOut,
                        destructive: true,
                        onPressed: busy ? null : () => onDelete(profile),
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                ShadSwitch(
                  value: !profile.disabled,
                  onChanged: busy
                      ? null
                      : (enabled) => onToggleDisabled(profile, !enabled),
                ),
                const Spacer(),
                _AccountActionButton(
                  label: 'Buckets',
                  icon: LucideIcons.listFilter,
                  onPressed: busy ? null : () => onManageBuckets(profile),
                ),
                const SizedBox(width: 6),
                _AccountActionButton(
                  label: 'Edit',
                  icon: LucideIcons.pencil,
                  onPressed: busy ? null : () => onEdit(profile),
                ),
                const SizedBox(width: 6),
                _AccountActionButton(
                  label: 'Remove',
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
    required this.onManageBuckets,
    required this.onToggleDisabled,
    required this.status,
    required this.statusError,
  });

  final ProfileInfo profile;
  final bool busy;
  final ValueChanged<ProfileInfo> onEdit;
  final ValueChanged<ProfileInfo> onDelete;
  final ValueChanged<ProfileInfo> onManageBuckets;
  final void Function(ProfileInfo profile, bool disabled) onToggleDisabled;
  final AccountStatus status;
  final String? statusError;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CloudStorageAccountList._actionColumnWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _AccountStatusChip(status: status, error: statusError),
          const SizedBox(width: 10),
          ShadSwitch(
            value: !profile.disabled,
            onChanged: busy
                ? null
                : (enabled) => onToggleDisabled(profile, !enabled),
          ),
          const SizedBox(width: 10),
          _AccountActionButton(
            label: '桶管理',
            icon: LucideIcons.listFilter,
            onPressed: busy ? null : () => onManageBuckets(profile),
          ),
          const SizedBox(width: 6),
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

/// Status chip for the account-management status column. Shows a small dot +
/// label. Uses mutedForeground colors so it never reads as a hover/theme change
/// (per the hover visual rule, an idle column must look identical at hover).
class _AccountStatusChip extends StatelessWidget {
  const _AccountStatusChip({required this.status, this.error});

  final AccountStatus status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final (label, color) = switch (status) {
      AccountStatus.ok => ('正常', const Color(0xFF16A34A)),
      AccountStatus.error => ('连接失败', const Color(0xFFDC2626)),
      AccountStatus.disabled => ('已禁用', theme.colorScheme.mutedForeground),
      AccountStatus.checking => ('检测中', theme.colorScheme.mutedForeground),
    };
    return Tooltip(
      message: status == AccountStatus.error
          ? (error?.isNotEmpty == true ? error! : '连接失败')
          : label,
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status == AccountStatus.checking
                  ? theme.colorScheme.mutedForeground.withValues(alpha: 0.4)
                  : color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: status == AccountStatus.checking
                  ? theme.colorScheme.mutedForeground
                  : (status == AccountStatus.ok
                        ? theme.colorScheme.foreground
                        : color),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountActionButton extends StatefulWidget {
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
  State<_AccountActionButton> createState() => _AccountActionButtonState();
}

class _AccountActionButtonState extends State<_AccountActionButton> {
  // Track hover locally so we can paint the same neutral wash the file rows
  // use (ListInteractionColors.fromTheme). We intentionally do NOT use
  // ShadButton.ghost's own hover background: the shadcn ghost theme paints
  // `colorScheme.accent`, which is visibly stronger than the row wash and
  // makes a hovered action button read as a different component. Rendering
  // a transparent button on top of our own AnimatedContainer keeps hover a
  // subtle background change only, per AGENTS.md hover style rule.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interaction = ListInteractionColors.fromTheme(theme);
    final color = widget.destructive
        ? theme.colorScheme.destructive
        : theme.colorScheme.primary;
    final enabled = widget.onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: enabled
                ? interaction.rowBackground(
                    selected: false,
                    hovered: _hovered,
                    pressed: false,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(fontSize: 11.5, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountIcon extends StatelessWidget {
  const _AccountIcon();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox(
      width: 32,
      height: 32,
      child: Icon(
        // Protocol remains visible in the type label; accounts share one icon.
        LucideIcons.cloud,
        size: 18,
        color: theme.colorScheme.primary,
      ),
    );
  }
}

class _ListDragHandle extends StatelessWidget {
  const _ListDragHandle();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Icon(
      LucideIcons.gripVertical,
      size: 14,
      color: theme.colorScheme.mutedForeground,
    );
  }
}
