// 账号管理列表提供和桶列表一致的卡片/表格双视图。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'cloud_storage_account_card.dart';
part 'cloud_storage_account_list_support.dart';

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
                    // Flutter 3.41 needs this until the minimum SDK is raised.
                    // ignore: deprecated_member_use
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
