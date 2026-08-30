// 首次启动引导页的「从备份存储还原」流程：连接备份目标、列快照、确认后还原。
// 密码重试逻辑复用 config_backup_restore.dart，避免与设置页历史弹窗分叉。
part of 'config_setup_page.dart';

bool _isPresetEndpoint(String value) {
  final endpoint = value.trim();
  return endpoint.isEmpty ||
      endpoint == _kDefaultS3Endpoint ||
      endpoint == _kDefaultWebDavEndpoint ||
      endpoint == _kBaiduPanEndpoint;
}

String _defaultEndpointFor(StorageType type) {
  return switch (type) {
    StorageType.s3 => _kDefaultS3Endpoint,
    StorageType.webdav => _kDefaultWebDavEndpoint,
    StorageType.baiduPan => _kBaiduPanEndpoint,
    StorageType.ftp || StorageType.sftp => '',
  };
}

/// Extension that opens the backup-restore flow from the first-run setup page.
/// On a fresh machine the user may have no accounts but does have remote
/// backup snapshots they want to pull in.
extension _ConfigSetupRestore on _ConfigSetupPageState {
  Future<void> _openRestoreFromBackup() async {
    // Step 1: check whether backup settings already exist locally.
    var target = const ConfigBackupTarget();
    try {
      final settings = await widget.api.loadConfigBackupSettings();
      if (settings.target.isReady) target = settings.target;
    } catch (_) {
      // Ignore — treat as unconfigured.
    }
    if (!target.isReady) {
      // No usable local target — let the user connect a backup storage inline.
      final configured = await _promptForBackupStorage();
      if (configured == null) return;
      target = configured;
    }
    if (!mounted) return;
    // Step 2: list snapshots using the (possibly inline) target.
    await _showSnapshotList(target);
  }

  /// Opens the standalone storage dialog so the user can connect a backup
  /// storage without first creating an account. Returns the resolved target
  /// (with bucket + prefix) or null if cancelled.
  Future<ConfigBackupTarget?> _promptForBackupStorage() async {
    RemoteStorageConfig? storageConfig;
    await showAppModal<void>(
      context: context,
      builder: (_) => CloudStorageAccountDialog(
        api: widget.api,
        simpleMode: true,
        onListBuckets: widget.api.listBuckets,
        onStartBaiduPanAuthorization: widget.api.startBaiduPanAuthorization,
        onAuthorizeBaiduPan: widget.api.authorizeBaiduPan,
        onSave: (config) async {
          if (!config.isConfigured) return false;
          storageConfig = config;
          return true;
        },
      ),
    );
    if (storageConfig == null || !storageConfig!.isConfigured) return null;

    // Pick save location (bucket + prefix) from the connected storage.
    if (!mounted) return null;
    final location = await _pickBackupLocation(storageConfig!);
    if (location == null) return null;

    return ConfigBackupTarget(
      standalone: storageConfig,
      bucket: location.bucket,
      prefix: location.prefix,
    );
  }

  /// Opens the remote directory picker on the given storage config so the
  /// user can choose where backups live. Returns the bucket + prefix or null.
  Future<({String bucket, String prefix})?> _pickBackupLocation(
    RemoteStorageConfig config,
  ) async {
    late ConfigBackupPickerModel pickerModel;
    try {
      final buckets = await widget.api.listBuckets(config);
      pickerModel = buildConfigBackupPickerModel(
        config: config,
        buckets: buckets,
        profileName: '__restore__',
      );
    } catch (error) {
      if (mounted) {
        showAppErrorToast(
          context,
          title: '读取存储桶失败',
          message: configBackupFriendlyError(error),
        );
      }
      return null;
    }
    if (!mounted) return null;
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
        bucket: initialEntry?.bucket.name ?? '',
        prefix: '',
        profileName: initialProfileName,
        config: config,
      ),
    );
    if (result == null || result.bucket.trim().isEmpty) return null;
    return (bucket: result.bucket, prefix: result.prefix);
  }

  /// Shows the snapshot list modal for the given target. Uses the inline-target
  /// bridge methods so it works even before local settings are persisted.
  Future<void> _showSnapshotList(ConfigBackupTarget target) async {
    final snapshots = <ConfigBackupSnapshot>[];
    var loading = true;
    var requestStarted = false;
    var errorMessage = '';

    await showAppModal<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (!requestStarted) {
              requestStarted = true;
              widget.api
                  .listConfigBackupsWithTarget(target)
                  .then((items) {
                    snapshots.clear();
                    snapshots.addAll(items);
                    loading = false;
                    if (ctx.mounted) setDialogState(() {});
                  })
                  .catchError((e) {
                    errorMessage = configBackupFriendlyError(e);
                    loading = false;
                    if (ctx.mounted) setDialogState(() {});
                  });
            }
            return AppShadDialog(
              title: const Text('从备份存储还原'),
              description: const Text('选择一份远端备份快照进行还原。'),
              constraints: const BoxConstraints(maxWidth: 520),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: AppLoadingIndicator()),
                      )
                    else if (errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          errorMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: ShadTheme.of(ctx).colorScheme.destructive,
                          ),
                        ),
                      )
                    else if (snapshots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          '没有找到配置备份。请确认选中了存放备份快照的目录。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: ShadTheme.of(
                              ctx,
                            ).colorScheme.mutedForeground,
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 340),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: snapshots.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (_, index) {
                            final s = snapshots[index];
                            final label = configBackupSnapshotPrimaryLabel(s);
                            return _RestoreSnapshotTile(
                              label: label,
                              latest: index == 0,
                              encrypted: s.encrypted,
                              onRestore: () async {
                                // 先尝试用本地已有的（或空的）密码还原；
                                // 只要解密失败就循环弹密码框让用户重试，
                                // 其它错误才直接报错退出。
                                final confirmed = await showAppConfirmModal(
                                  context: ctx,
                                  title: const Text('还原此配置备份？'),
                                  description: Text('将用 $label 还原账号和配置。'),
                                  confirmLabel: '还原',
                                  destructive: true,
                                );
                                if (confirmed != true) return;
                                if (!ctx.mounted) return;
                                Navigator.of(dialogContext).pop();
                                if (!mounted) return;
                                try {
                                  await restoreConfigBackupWithPasswordRetry(
                                    context: context,
                                    isMounted: () => mounted,
                                    api: widget.api,
                                    target: target,
                                    key: s.key,
                                    label: label,
                                  );
                                  if (!mounted) return;
                                  showAppToast(
                                    context,
                                    title: '配置已还原',
                                    message: label,
                                  );
                                  widget.onSaved();
                                } on ConfigBackupRestoreCancelled {
                                  // 用户取消密码输入：静默退出。
                                } catch (e) {
                                  if (!mounted) return;
                                  showAppErrorToast(
                                    context,
                                    title: '还原失败',
                                    message: configBackupFriendlyError(e),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ShadButton.outline(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('取消'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RestoreSnapshotTileState extends State<_RestoreSnapshotTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interaction = ListInteractionColors.fromTheme(theme);
    final bg = interaction.rowBackground(
      selected: false,
      hovered: _hovered,
      pressed: false,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.border),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            if (widget.encrypted) ...[
              Icon(
                Icons.lock_outline,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.foreground,
                ),
              ),
            ),
            if (widget.latest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '最新',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 10),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: widget.onRestore,
              child: const Text('还原'),
            ),
          ],
        ),
      ),
    );
  }
}
