// Account table support widgets keep the public account-list module focused.
part of 'cloud_storage_account_list.dart';

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
    final statusMessage = status == AccountStatus.error
        ? (error?.isNotEmpty == true ? error! : '连接失败')
        : label;
    // Android 触屏没有 hover tooltip；Semantics 让错误详情对读屏/辅助
    // 技术可读，桌面 Tooltip 保持不变。
    return Semantics(
      label: statusMessage,
      child: Tooltip(
        message: statusMessage,
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
    this.dense = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  /// Dense is the compact desktop-table style; the mobile card uses the
  /// non-dense variant to keep a full 48dp touch target.
  final bool dense;

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
        child: Container(
          alignment: widget.dense ? null : Alignment.center,
          constraints: widget.dense
              ? null
              : const BoxConstraints(minHeight: 48),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: widget.dense
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                Icon(widget.icon, size: widget.dense ? 13 : 16, color: color),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.dense ? 11.5 : 13,
                    color: color,
                  ),
                ),
              ],
            ),
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
