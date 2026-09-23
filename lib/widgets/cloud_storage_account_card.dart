// 账号管理卡片视图：cloud_storage_account_list.dart 的 part 文件，承载移动/桌面
// 共用的账号卡、状态 chip、行动作按钮与拖拽把手等纯展示件。

part of 'cloud_storage_account_list.dart';

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
        ? '${CloudStorageAccountList._profileTitle(profile)}（已禁用）'
        : CloudStorageAccountList._profileTitle(profile);
    final content = Column(
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
              SizedBox(
                height: 48,
                child: Row(
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
                        profile.disabled ? '已禁用' : '已启用',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _AccountActionButton(
                      label: '桶管理',
                      icon: LucideIcons.listFilter,
                      dense: false,
                      onPressed: busy ? null : () => onManageBuckets(profile),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AccountActionButton(
                      label: '编辑',
                      icon: LucideIcons.pencil,
                      dense: false,
                      onPressed: busy ? null : () => onEdit(profile),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AccountActionButton(
                      label: '退出',
                      icon: LucideIcons.logOut,
                      destructive: true,
                      dense: false,
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
        ],
      );
    // 账号块保持带边框卡片(用户裁决恢复;无边框基线仅适用于文件/回收站/
    // 任务列表页)。
    return ShadCard(padding: const EdgeInsets.all(14), child: content);
  }
}
