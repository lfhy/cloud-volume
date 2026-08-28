// Modal list for remote configuration backup snapshots.
// Keeps potentially long history out of the settings page body.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/config_backup_restore.dart';
import 'package:remote_storage/widgets/settings_config_backup_labels.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ConfigBackupHistoryDialog extends StatefulWidget {
  const ConfigBackupHistoryDialog({
    super.key,
    required this.api,
    required this.initialSnapshots,
    required this.settings,
    required this.onSnapshotsChanged,
    required this.onSettingsChanged,
    required this.onRestored,
    required this.onDelete,
  });

  final RemoteStorageGateway api;
  final List<ConfigBackupSnapshot> initialSnapshots;
  final ConfigBackupSettings settings;
  final ValueChanged<List<ConfigBackupSnapshot>> onSnapshotsChanged;
  final ValueChanged<ConfigBackupSettings> onSettingsChanged;
  final ValueChanged<BootstrapState> onRestored;
  final Future<void> Function(ConfigBackupSnapshot snapshot) onDelete;

  @override
  State<ConfigBackupHistoryDialog> createState() =>
      _ConfigBackupHistoryDialogState();
}

class _ConfigBackupHistoryDialogState extends State<ConfigBackupHistoryDialog> {
  late List<ConfigBackupSnapshot> _snapshots;
  late ConfigBackupSettings _settings;
  bool _loading = false;
  bool _restoring = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _snapshots = List<ConfigBackupSnapshot>.from(widget.initialSnapshots);
    _settings = widget.settings;
    // Revalidate on open so the settings card can keep only a short summary.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.listConfigBackups();
      if (!mounted) return;
      setState(() => _snapshots = items);
      widget.onSnapshotsChanged(items);
    } catch (error) {
      if (mounted) setState(() => _error = configBackupFriendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(ConfigBackupSnapshot snapshot) async {
    final label = configBackupSnapshotPrimaryLabel(snapshot);

    // Always confirm first — simple and predictable.
    final confirmed = await showAppConfirmModal(
      context: context,
      title: const Text('还原此配置备份？'),
      description: Text(
        '将用 $label 替换当前账号、代理和显示排序；备份目标会保留，方便继续管理备份。',
      ),
      confirmLabel: '还原配置',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _restoring = true);
    try {
      var usedPasswordRetry = false;
      BootstrapState state;
      try {
        // 先走本地已保存的密码（或空密码）。解密失败再弹密码框重试，
        // 其它错误直接抛出，避免把网络/解析失败误当成密码问题。
        state = await widget.api.restoreConfigBackup(snapshot.key);
      } catch (firstError) {
        if (!isConfigBackupDecryptionError(firstError)) {
          rethrow;
        }
        // 本地密码已经证明不对：直接弹密码框，不要再拿同一密码重试一轮。
        // with-target 成功后 bridge 会把含新密码的 target 固化到本地设置。
        if (!mounted) return;
        usedPasswordRetry = true;
        state = await restoreConfigBackupWithPasswordRetry(
          context: context,
          isMounted: () => mounted,
          api: widget.api,
          target: _settings.target,
          key: snapshot.key,
          label: label,
          skipInitialAttempt: true,
        );
      }
      if (usedPasswordRetry) {
        await _syncSettingsAfterPasswordRestore();
      }
      if (!mounted) return;
      widget.onRestored(state);
      showAppToast(context, title: '配置已还原', message: label);
    } on ConfigBackupRestoreCancelled {
      // 用户取消密码输入：静默退出，不弹「还原失败」。
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context,
            title: '还原失败', message: configBackupFriendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// with-target 还原成功后 bridge 已写入新密码；这里再读一遍同步 UI。
  Future<void> _syncSettingsAfterPasswordRestore() async {
    try {
      final latest = await widget.api.loadConfigBackupSettings();
      if (!mounted) return;
      setState(() => _settings = latest);
      widget.onSettingsChanged(latest);
    } catch (_) {
      // Non-fatal: restore itself already succeeded.
    }
  }

  Future<void> _delete(ConfigBackupSnapshot snapshot) async {
    final label = configBackupSnapshotPrimaryLabel(snapshot);
    final confirmed = await showAppConfirmModal(
      context: context,
      title: const Text('删除此备份？'),
      description: Text('删除后无法恢复。$label'),
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete(snapshot);
      if (!mounted) return;
      final remaining = _snapshots.where((s) => s.key != snapshot.key).toList();
      setState(() => _snapshots = remaining);
      widget.onSnapshotsChanged(remaining);
      if (mounted) {
        showAppToast(context, title: '已删除', message: label);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = configBackupFriendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    // Note: `_loading` (background refresh) intentionally does NOT lock the
    // action buttons. Locking them during the open-time refresh caused the
    // first tap on 还原/删除 to be silently swallowed while the post-frame
    // list refresh was still running — the classic "first click does nothing"
    // bug. Only an active restore/delete disables the row actions.
    final busy = _restoring || _deleting;
    return ShadDialog(
      title: const Text('配置备份历史'),
      description: const Text('按时间查看远端加密快照。还原会替换当前账号、代理和显示排序。'),
      constraints: const BoxConstraints(maxWidth: 560),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _loading && _snapshots.isEmpty
                        ? '正在读取…'
                        : _snapshots.isEmpty
                            ? '暂无备份'
                            : '共 ${_snapshots.length} 份备份',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  // `busy` no longer includes background `_loading`, so keep
                  // the refresh button explicitly disabled while a refresh is
                  // running to avoid stacking concurrent list calls.
                  onPressed: (_loading || busy) ? null : _refresh,
                  child: Text(_loading ? '刷新中…' : '刷新'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading && _snapshots.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: AppLoadingIndicator()),
              )
            else if (_snapshots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 22,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 28,
                        color: theme.colorScheme.mutedForeground,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '还没有可用备份',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.foreground,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '保存备份目标后，在设置页点“立即备份”创建第一份快照。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _snapshots.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final snapshot = _snapshots[index];
                    return _BackupSnapshotTile(
                      snapshot: snapshot,
                      latest: index == 0,
                      busy: busy,
                      onRestore: () => _restore(snapshot),
                      onDelete: () => _delete(snapshot),
                    );
                  },
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.destructive,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: ShadButton.outline(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hover-aware snapshot row used inside the history modal.
class _BackupSnapshotTile extends StatefulWidget {
  const _BackupSnapshotTile({
    required this.snapshot,
    required this.latest,
    required this.busy,
    required this.onRestore,
    required this.onDelete,
  });

  final ConfigBackupSnapshot snapshot;
  final bool latest;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  State<_BackupSnapshotTile> createState() => _BackupSnapshotTileState();
}

class _BackupSnapshotTileState extends State<_BackupSnapshotTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interaction = ListInteractionColors.fromTheme(theme);
    final background = interaction.rowBackground(
      selected: false,
      hovered: _hovered,
      pressed: false,
    );
    final primary = configBackupSnapshotPrimaryLabel(widget.snapshot);
    final secondary = configBackupSnapshotSecondaryLabel(widget.snapshot);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.border),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          primary,
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
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
                    ],
                  ),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      secondary,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: widget.busy ? null : widget.onRestore,
              child: const Text('还原'),
            ),
            const SizedBox(width: 6),
            ShadButton.destructive(
              size: ShadButtonSize.sm,
              onPressed: widget.busy ? null : widget.onDelete,
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }
}

