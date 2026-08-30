part of 'settings_config_backup_target.dart';

// Owns the backup-only remote directory picker and its hover-aware trigger.
StorageType? _configBackupTargetStorageType({
  required ConfigBackupTarget target,
  required List<ProfileInfo> profiles,
}) {
  if (target.profileName.isEmpty) return target.standalone?.storageType;
  for (final profile in profiles) {
    if (profile.name == target.profileName) return profile.storageType;
  }
  return null;
}

class _SaveLocationPicker extends StatefulWidget {
  const _SaveLocationPicker({
    required this.theme,
    required this.api,
    required this.target,
    required this.storageType,
    required this.busy,
    required this.onPicked,
  });

  final ShadThemeData theme;
  final RemoteStorageGateway api;
  final ConfigBackupTarget target;
  final StorageType? storageType;
  final bool busy;
  final void Function(String bucket, String prefix) onPicked;

  @override
  State<_SaveLocationPicker> createState() => _SaveLocationPickerState();
}

class _SaveLocationPickerState extends State<_SaveLocationPicker> {
  Future<RemoteStorageConfig?> _resolveConfig() async {
    if (widget.target.profileName.isEmpty) return widget.target.standalone;
    try {
      return await widget.api.loadProfile(widget.target.profileName);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openPicker() async {
    final config = await _resolveConfig();
    if (!mounted) return;
    if (config == null || !config.isConfigured) {
      showAppErrorToast(
        context,
        title: '无法打开目录选择器',
        message: '请先选择一个已配置的备份存储。',
      );
      return;
    }
    final profileName = widget.target.profileName.isEmpty
        ? '__standalone__'
        : widget.target.profileName;
    late ConfigBackupPickerModel pickerModel;
    try {
      final buckets = await widget.api.listBuckets(config);
      pickerModel = buildConfigBackupPickerModel(
        config: config,
        buckets: buckets,
        profileName: profileName,
      );
    } catch (error) {
      if (mounted) {
        showAppErrorToast(
          context,
          title: '读取存储桶失败',
          message: configBackupFriendlyError(error),
        );
      }
      return;
    }
    if (!mounted) return;
    final hasSavedLocation = widget.target.bucket.trim().isNotEmpty;
    final initialEntry = pickerModel.initialEntry;
    final initialProfileName =
        initialEntry?.profileName ??
        (pickerModel.entries.isEmpty
            ? ''
            : pickerModel.entries.first.profileName);
    final result = await showRemoteDirectoryPicker(
      context: context,
      api: widget.api,
      buckets: pickerModel.entries,
      initial: RemoteDirectoryResult(
        // A saved target must remain exact; only a fresh synthetic-root target
        // opens its one virtual bucket directly.
        bucket: hasSavedLocation
            ? widget.target.bucket
            : initialEntry?.bucket.name ?? '',
        prefix: hasSavedLocation ? widget.target.prefix : '',
        profileName: initialProfileName,
        config: config,
      ),
    );
    if (result != null) widget.onPicked(result.bucket, result.prefix);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final hasLocation = widget.target.bucket.trim().isNotEmpty;
    final displayBucket = widget.storageType == null
        ? widget.target.bucket
        : configBackupBucketDisplayName(
            storageType: widget.storageType!,
            bucket: widget.target.bucket,
          );
    final preview = configBackupPathPreview(
      bucket: widget.target.bucket,
      prefix: widget.target.prefix,
      displayBucket: displayBucket,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '保存位置',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 6),
        _PickerButton(
          theme: theme,
          label: hasLocation ? preview : '选择保存位置',
          hasLocation: hasLocation,
          enabled: !widget.busy,
          onPressed: _openPicker,
        ),
      ],
    );
  }
}

/// Clickable "选择保存位置" button (hover-aware per AGENTS.md rules).
class _PickerButton extends StatefulWidget {
  const _PickerButton({
    required this.theme,
    required this.label,
    required this.hasLocation,
    required this.enabled,
    required this.onPressed,
  });

  final ShadThemeData theme;
  final String label;
  final bool hasLocation;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_PickerButton> createState() => _PickerButtonState();
}

class _PickerButtonState extends State<_PickerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final interaction = ListInteractionColors.fromTheme(theme);
    final bg = interaction.rowBackground(
      selected: false,
      hovered: _hovered && widget.enabled,
      pressed: false,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(bg, theme.colorScheme.background),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.border),
          ),
          child: Row(
            children: [
              Icon(
                widget.hasLocation
                    ? Icons.folder_open_rounded
                    : Icons.create_new_folder_outlined,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.hasLocation
                        ? theme.colorScheme.foreground
                        : theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
