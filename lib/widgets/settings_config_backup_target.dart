// Backup target configuration: account selector, standalone storage dialog,
// single save-location picker, and encryption-key info modal.
// Extracted from settings_config_backup_section.dart to stay under 500 lines.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/widgets/settings_config_backup_cards.dart';
import 'package:remote_storage/widgets/settings_config_backup_labels.dart';
import 'package:remote_storage/widgets/settings_config_backup_section.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/utils/config_backup_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'settings_config_backup_location_picker.dart';
part 'settings_config_backup_encryption.dart';

/// Renders the backup-target sub-card shown only when backup is enabled.
/// The selector offers existing accounts plus a "独立备份存储" option whose
/// connection form opens lazily on click. Save location is a single remote
/// directory picker (bucket + prefix in one action).
class ConfigBackupTargetSection extends StatelessWidget {
  const ConfigBackupTargetSection({
    super.key,
    required this.theme,
    required this.api,
    required this.profiles,
    required this.target,
    required this.busy,
    required this.backingUp,
    required this.encryptionEnabled,
    required this.onSelectTarget,
    required this.onConfigureStandalone,
    required this.onPickSaveLocation,
    required this.onToggleEncryption,
    required this.onPasswordSaved,
    required this.onBackupNow,
  });

  final ShadThemeData theme;
  final RemoteStorageGateway api;
  final List<ProfileInfo> profiles;
  final ConfigBackupTarget target;
  final bool busy;
  final bool backingUp;
  final bool encryptionEnabled;
  final ValueChanged<String> onSelectTarget;
  final ValueChanged<RemoteStorageConfig> onConfigureStandalone;
  final void Function(String bucket, String prefix) onPickSaveLocation;
  final ValueChanged<bool> onToggleEncryption;
  final ValueChanged<String> onPasswordSaved;
  final VoidCallback onBackupNow;

  @override
  Widget build(BuildContext context) {
    // Default state: no profile and no standalone configured yet.
    final hasProfile = target.profileName.isNotEmpty;
    final hasStandalone =
        target.standalone != null && target.standalone!.isConfigured;
    final selectorValue = hasProfile
        ? target.profileName
        : (hasStandalone ? kStandaloneTargetValue : kUnsetTargetValue);
    final targetStorageType = _configBackupTargetStorageType(
      target: target,
      profiles: profiles,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '备份存储',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 8),
        _BackupTargetSelector(
          theme: theme,
          profiles: profiles,
          value: selectorValue,
          enabled: !busy,
          onChanged: onSelectTarget,
        ),
        const SizedBox(height: 10),
        _StandaloneTargetCard(
          theme: theme,
          api: api,
          profiles: profiles,
          target: target,
          busy: busy,
          onConfigured: onConfigureStandalone,
        ),
        // Only show save-location picker, encryption key info, and backup
        // button once the storage connection itself is usable.
        if (target.isReady ||
            (target.profileName.isNotEmpty) ||
            (target.standalone != null && target.standalone!.isConfigured)) ...[
          const SizedBox(height: 12),
          _SaveLocationPicker(
            theme: theme,
            api: api,
            target: target,
            storageType: targetStorageType,
            busy: busy,
            onPicked: onPickSaveLocation,
          ),
          const SizedBox(height: 8),
          _EncryptionSection(
            theme: theme,
            encryptionEnabled: encryptionEnabled,
            hasPassword: target.backupPassword.trim().isNotEmpty,
            busy: busy,
            onToggleEncryption: onToggleEncryption,
            onPasswordSaved: onPasswordSaved,
          ),
          if (encryptionEnabled) ...[
            const SizedBox(height: 8),
            _EncryptionPasswordRow(
              theme: theme,
              hasPassword: target.backupPassword.trim().isNotEmpty,
              busy: busy,
              onPasswordSaved: onPasswordSaved,
            ),
          ],
          const SizedBox(height: 14),
          ShadButton(
            onPressed: target.isReady && !busy ? onBackupNow : null,
            child: Text(backingUp ? '备份中…' : '立即备份'),
          ),
        ],
      ],
    );
  }
}

/// Shown when encryption is enabled: a button to set/change/clear password
/// plus a warning line if no password is configured yet.
class _EncryptionPasswordRow extends StatefulWidget {
  const _EncryptionPasswordRow({
    required this.theme,
    required this.hasPassword,
    required this.busy,
    required this.onPasswordSaved,
  });

  final ShadThemeData theme;
  final bool hasPassword;
  final bool busy;
  final ValueChanged<String> onPasswordSaved;

  @override
  State<_EncryptionPasswordRow> createState() => _EncryptionPasswordRowState();
}

class _EncryptionPasswordRowState extends State<_EncryptionPasswordRow> {
  late final TextEditingController _pwdController;
  late final TextEditingController _confirmController;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _pwdController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _pwdController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _openModal() async {
    _pwdController.clear();
    _confirmController.clear();
    _obscure = true;
    String? savedPassword;
    await showAppModalDialog<void>(
      context: context,
      title: Text(widget.hasPassword ? '修改加密密码' : '设置加密密码'),
      description: const Text('加密密码不依赖连接地址或凭证，换机器、换网络地址都不影响解密。请妥善保管，丢失后无法找回。'),
      maxWidth: 440,
      child: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CloudStorageLabeledField(
                label: widget.hasPassword ? '新密码' : '加密密码',
                child: ShadInput(
                  controller: _pwdController,
                  obscureText: _obscure,
                  placeholder: const Text('输入加密密码'),
                ),
              ),
              const SizedBox(height: 14),
              CloudStorageLabeledField(
                label: '确认密码',
                child: ShadInput(
                  controller: _confirmController,
                  obscureText: _obscure,
                  placeholder: const Text('再次输入密码'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ShadSwitch(
                    value: !_obscure,
                    onChanged: (v) => setDialogState(() => _obscure = !v),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '显示密码',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.theme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (widget.hasPassword)
          Builder(
            builder: (dialogContext) => ShadButton.outline(
              onPressed: () {
                savedPassword = '';
                Navigator.of(dialogContext).pop();
              },
              child: const Text('清除密码'),
            ),
          ),
        Builder(
          builder: (dialogContext) => ShadButton(
            onPressed: () {
              final pwd = _pwdController.text.trim();
              final confirm = _confirmController.text.trim();
              if (pwd.isEmpty) return;
              if (pwd != confirm) {
                showAppErrorToast(
                  context,
                  title: '密码不一致',
                  message: '两次输入的密码不匹配。',
                );
                return;
              }
              savedPassword = pwd;
              Navigator.of(dialogContext).pop();
            },
            child: const Text('保存'),
          ),
        ),
      ],
    );
    if (savedPassword != null && mounted) {
      widget.onPasswordSaved(savedPassword!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: widget.busy ? null : _openModal,
              child: Text(widget.hasPassword ? '修改加密密码' : '设置加密密码'),
            ),
            if (widget.hasPassword) ...[
              const SizedBox(width: 10),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: widget.busy
                    ? null
                    : () => widget.onPasswordSaved(''),
                child: const Text('重置备份密码'),
              ),
            ],
          ],
        ),
        if (!widget.hasPassword) ...[
          const SizedBox(height: 6),
          Text(
            '备份密码未配置，加密不会生效，备份将以明文存储。',
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }
}

// Dropdown: existing accounts vs standalone storage (no parenthetical).
class _BackupTargetSelector extends StatelessWidget {
  const _BackupTargetSelector({
    required this.theme,
    required this.profiles,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final List<ProfileInfo> profiles;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  String _label(String v) {
    if (v == kUnsetTargetValue) return '未配置';
    if (v == kStandaloneTargetValue) return '独立备份存储';
    for (final p in profiles) {
      if (p.name == v) return configBackupProfileLabel(p);
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ShadSelect<String>(
        key: ValueKey<String>(value),
        initialValue: value,
        minWidth: 320,
        selectedOptionBuilder: (context, selected) => Text(_label(selected)),
        options: [
          const ShadOption(value: kUnsetTargetValue, child: Text('未配置')),
          ...profiles.map(
            (p) => ShadOption(
              value: p.name,
              child: Text(configBackupProfileLabel(p)),
            ),
          ),
          const ShadOption(
            value: kStandaloneTargetValue,
            child: Text('独立备份存储'),
          ),
        ],
        onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
      ),
    );
  }
}

// Standalone: status card + lazy configure/edit button.
// Profile selected: read-only summary.
class _StandaloneTargetCard extends StatefulWidget {
  const _StandaloneTargetCard({
    required this.theme,
    required this.api,
    required this.profiles,
    required this.target,
    required this.busy,
    required this.onConfigured,
  });

  final ShadThemeData theme;
  final RemoteStorageGateway api;
  final List<ProfileInfo> profiles;
  final ConfigBackupTarget target;
  final bool busy;
  final ValueChanged<RemoteStorageConfig> onConfigured;

  @override
  State<_StandaloneTargetCard> createState() => _StandaloneTargetCardState();
}

class _StandaloneTargetCardState extends State<_StandaloneTargetCard> {
  bool get _isStandalone => widget.target.profileName.isEmpty;
  bool get _isConfigured =>
      widget.target.standalone != null &&
      widget.target.standalone!.isConfigured;

  Future<void> _openStandaloneDialog() async {
    final standalone = widget.target.standalone;
    RemoteStorageConfig? result;
    await showAppModal<void>(
      context: context,
      builder: (_) => CloudStorageAccountDialog(
        api: widget.api,
        initialConfig: standalone,
        editing: standalone != null,
        simpleMode: true,
        onListBuckets: widget.api.listBuckets,
        onStartBaiduPanAuthorization: widget.api.startBaiduPanAuthorization,
        onAuthorizeBaiduPan: widget.api.authorizeBaiduPan,
        onSave: (config) async {
          if (!config.isConfigured) return false;
          result = config;
          return true;
        },
      ),
    );
    if (result != null && mounted) widget.onConfigured(result!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    if (!_isStandalone) {
      // A profile is selected — show a read-only summary.
      return ConfigBackupStatusCard(
        theme: theme,
        title: configBackupTargetStatusTitle(
          target: widget.target,
          profiles: widget.profiles,
        ),
        detail: configBackupTargetStatusDetail(
          target: widget.target,
          profiles: widget.profiles,
        ),
      );
    }
    if (!_isConfigured) {
      // Standalone selected but not yet set up (or completely fresh) — show a
      // configure button to open the storage dialog.
      return ConfigBackupStatusCard(
        theme: theme,
        title: '尚未配置备份存储',
        detail: '点击右侧按钮配置一个不显示在账号列表中的备份连接。',
        trailing: ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: widget.busy ? null : _openStandaloneDialog,
          child: const Text('配置连接'),
        ),
      );
    }
    // Standalone fully configured — show summary + edit button.
    return ConfigBackupStatusCard(
      theme: theme,
      title: configBackupTargetStatusTitle(
        target: widget.target,
        profiles: widget.profiles,
      ),
      detail: configBackupTargetStatusDetail(
        target: widget.target,
        profiles: widget.profiles,
      ),
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: widget.busy ? null : _openStandaloneDialog,
        child: const Text('编辑连接'),
      ),
    );
  }
}
