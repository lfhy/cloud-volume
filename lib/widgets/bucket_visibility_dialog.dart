// Standalone dialog for managing an existing account's bucket visibility
// (allowlist + per-bucket display name / subdirectory). Separate from the
// account editor so editing connection fields never has to touch the bucket
// list endpoint, and so this dialog can be opened straight from the account
// list without entering the edit flow.
//
// Reuses _BucketVisibilityRow and _BucketSelectionCheckbox from the account
// wizard (part of cloud_storage_account_dialog.dart) so the row look and the
// hand-rolled checkbox stay identical across both entry points.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart'
    show BucketSelectionCheckbox;
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Opens a modal that lists every bucket for [config], lets the user toggle
/// which ones are visible (allowlist semantics) and edit each one's display
/// name / subdirectory, then persists the result via [onSave].
///
/// [onListBuckets] is used to fetch the live bucket list. [profileName] is
/// only used for logging/labels. Returns true if the user saved changes.
Future<bool> showBucketVisibilityDialog({
  required BuildContext context,
  required RemoteStorageGateway api,
  required RemoteStorageConfig config,
  required String profileName,
  required Future<bool> Function(Map<String, BucketViewSettings> views) onSave,
}) async {
  final result = await showAppModal<bool>(
    context: context,
    builder: (_) => _BucketVisibilityDialog(
      api: api,
      config: config,
      profileName: profileName,
      onSave: onSave,
    ),
  );
  return result ?? false;
}

class _BucketVisibilityDialog extends StatefulWidget {
  const _BucketVisibilityDialog({
    required this.api,
    required this.config,
    required this.profileName,
    required this.onSave,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final String profileName;
  final Future<bool> Function(Map<String, BucketViewSettings> views) onSave;

  @override
  State<_BucketVisibilityDialog> createState() =>
      _BucketVisibilityDialogState();
}

class _BucketVisibilityDialogState extends State<_BucketVisibilityDialog> {
  List<BucketInfo> _buckets = const [];
  Map<String, BucketViewSettings> _views = const {};
  bool _loading = true;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // Copy the incoming allowlist so the user edits a draft until Save.
    _views = Map<String, BucketViewSettings>.from(widget.config.bucketViews);
    _loadBuckets();
  }

  Future<void> _loadBuckets() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final buckets = await widget.api.listBuckets(widget.config);
      if (!mounted) return;
      setState(() {
        _buckets = buckets;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '无法读取桶列表：${describeBridgeError(error)}';
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final ok = await widget.onSave(Map<String, BucketViewSettings>.from(_views));
      if (!mounted) return;
      if (ok) {
        showAppToast(context, title: '桶管理已更新', message: widget.config.displayName);
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _saving = false;
          _errorText = '保存失败，请重试。';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = describeBridgeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDialog(
      title: const Text('桶列表显示设置'),
      description: Text(
        '账号：${widget.config.displayName.isEmpty ? widget.profileName : widget.config.displayName}',
      ),
      constraints: const BoxConstraints(maxWidth: 640),
      scrollable: true,
      child: _buildBody(theme),
    );
  }

  Widget _buildBody(ShadThemeData theme) {
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: AppLoadingIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '不选择任何桶表示动态显示全部桶，之后新增的桶也会自动出现。选择后将只显示选中的桶。',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        if (_errorText != null) ...[
          Text(
            _errorText!,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.destructive),
          ),
          const SizedBox(height: 10),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: _loadBuckets,
            child: const Text('重试'),
          ),
          const SizedBox(height: 10),
        ] else if (_buckets.isEmpty) ...[
          Text('当前账号没有可用桶。', style: theme.textTheme.small)
        ] else
          for (final bucket in _buckets) ...[
            _StandaloneBucketVisibilityRow(
              bucket: bucket,
              config: widget.config,
              api: widget.api,
              views: _views,
              onChanged: (views) => setState(() => _views = views),
            ),
            if (bucket != _buckets.last) const SizedBox(height: 8),
          ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ShadButton.outline(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            const SizedBox(width: 10),
            ShadButton(
              onPressed: _saving || _loading ? null : _save,
              child: _saving ? const Text('保存中...') : const Text('保存'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A standalone variant of the wizard's _BucketVisibilityRow. It owns its own
/// controllers and reads/writes the dialog's _views map directly, so it does
/// not depend on _CloudStorageAccountDialogState. Kept visually identical to
/// the wizard row via the same _BucketSelectionCheckbox widget.
class _StandaloneBucketVisibilityRow extends StatefulWidget {
  const _StandaloneBucketVisibilityRow({
    required this.bucket,
    required this.config,
    required this.api,
    required this.views,
    required this.onChanged,
  });

  final BucketInfo bucket;
  final RemoteStorageConfig config;
  final RemoteStorageGateway api;
  final Map<String, BucketViewSettings> views;
  final ValueChanged<Map<String, BucketViewSettings>> onChanged;

  @override
  State<_StandaloneBucketVisibilityRow> createState() =>
      _StandaloneBucketVisibilityRowState();
}

class _StandaloneBucketVisibilityRowState
    extends State<_StandaloneBucketVisibilityRow> {
  late final TextEditingController _displayController;
  late final TextEditingController _prefixController;

  bool get selected => widget.views.containsKey(widget.bucket.name);

  @override
  void initState() {
    super.initState();
    final view = widget.views[widget.bucket.name];
    _displayController = TextEditingController(text: view?.displayName ?? '');
    _prefixController = TextEditingController(text: view?.rootPrefix ?? '');
  }

  @override
  void didUpdateWidget(covariant _StandaloneBucketVisibilityRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bucket.name != widget.bucket.name) {
      final view = widget.views[widget.bucket.name];
      _displayController.text = view?.displayName ?? '';
      _prefixController.text = view?.rootPrefix ?? '';
    }
  }

  @override
  void dispose() {
    _displayController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  void _sync() {
    if (!selected) return;
    widget.onChanged({
      ...widget.views,
      widget.bucket.name: BucketViewSettings(
        displayName: _displayController.text,
        rootPrefix: _prefixController.text,
      ),
    });
  }

  Future<void> _chooseDirectory() async {
    final config = widget.config.copyWith(
      bucketViews: const <String, BucketViewSettings>{},
      rootPrefix: widget.config.rootPrefix,
    );
    final entry = FileManagerBucketEntry.fromBucketInfo(
      bucket: widget.bucket,
      profileName: 'bucket-visibility',
      sourceLabel: config.displayName,
      config: config,
    );
    final selected = await showRemoteDirectoryPicker(
      context: context,
      api: widget.api,
      buckets: <FileManagerBucketEntry>[entry],
      initial: RemoteDirectoryResult(
        bucket: widget.bucket.name,
        prefix: _prefixController.text,
        profileName: entry.profileName,
        config: config,
      ),
    );
    if (selected == null || !mounted) return;
    _prefixController.text = selected.prefix;
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BucketSelectionCheckbox(
                value: selected,
                onChanged: (value) {
                  final next = Map<String, BucketViewSettings>.from(widget.views);
                  if (value) {
                    next[widget.bucket.name] = const BucketViewSettings();
                  } else {
                    next.remove(widget.bucket.name);
                  }
                  widget.onChanged(next);
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.bucket.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (selected) ...[
            const SizedBox(height: 6),
            CloudStorageLabeledField(
              label: '显示名称（可选）',
              child: ShadInput(
                controller: _displayController,
                placeholder: Text(widget.bucket.name),
                onChanged: (_) => _sync(),
              ),
            ),
            const SizedBox(height: 8),
            CloudStorageLabeledField(
              label: '子目录（可选）',
              child: Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: _prefixController,
                      placeholder: const Text('桶根目录'),
                      onChanged: (_) => _sync(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton.outline(
                    onPressed: _chooseDirectory,
                    child: const Row(
                      children: [
                        Icon(LucideIcons.folderOpen, size: 16),
                        SizedBox(width: 4),
                        Text('选择'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
