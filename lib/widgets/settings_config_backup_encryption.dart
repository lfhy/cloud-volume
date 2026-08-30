part of 'settings_config_backup_target.dart';

// Renders the backup encryption switch separately from the password modal.
class _EncryptionSection extends StatelessWidget {
  const _EncryptionSection({
    required this.theme,
    required this.encryptionEnabled,
    required this.hasPassword,
    required this.busy,
    required this.onToggleEncryption,
    required this.onPasswordSaved,
  });

  final ShadThemeData theme;
  final bool encryptionEnabled;
  final bool hasPassword;
  final bool busy;
  final ValueChanged<bool> onToggleEncryption;
  final ValueChanged<String> onPasswordSaved;

  @override
  Widget build(BuildContext context) {
    return ConfigBackupSwitchCard(
      theme: theme,
      title: '备份加密',
      description: encryptionEnabled
          ? (hasPassword
                ? '已启用加密，备份将使用密码加密存储。'
                : '已启用加密但未设置密码，加密不会生效，备份将以明文存储。')
          : '关闭后备份以明文存储，不进行加密。',
      value: encryptionEnabled,
      enabled: !busy,
      onChanged: onToggleEncryption,
    );
  }
}
