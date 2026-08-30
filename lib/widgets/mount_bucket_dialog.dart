// Mount settings dialog separates access mode from platform-specific presentation.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/mount_engine_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Future<MountBucketOptions?> showMountBucketDialog(
  BuildContext context, {
  required String bucket,
  bool showWindowsMountMode = false,
  List<String> availableDriveLetters = const <String>[],
  WindowsMountEngine? currentEngine,
  bool winFspAvailable = false,
  bool forceReadOnly = false,
}) {
  return showAppModal<MountBucketOptions?>(
    context: context,
    builder: (dialogContext) => _MountBucketDialog(
      bucket: bucket,
      showWindowsMountMode: showWindowsMountMode,
      availableDriveLetters: availableDriveLetters,
      currentEngine: currentEngine,
      winFspAvailable: winFspAvailable,
      forceReadOnly: forceReadOnly,
    ),
  );
}

class _MountBucketDialog extends StatefulWidget {
  const _MountBucketDialog({
    required this.bucket,
    required this.showWindowsMountMode,
    required this.availableDriveLetters,
    required this.currentEngine,
    required this.winFspAvailable,
    required this.forceReadOnly,
  });

  final String bucket;
  final bool showWindowsMountMode;
  final List<String> availableDriveLetters;
  final WindowsMountEngine? currentEngine;
  final bool winFspAvailable;
  final bool forceReadOnly;

  @override
  State<_MountBucketDialog> createState() => _MountBucketDialogState();
}

class _MountBucketDialogState extends State<_MountBucketDialog> {
  String _mountPath = '';
  bool _readOnly = false;
  String? _driveLetter;
  WindowsMountEngine? _engine;

  @override
  void initState() {
    super.initState();
    _readOnly = widget.forceReadOnly;
    final hasDrive = widget.availableDriveLetters.isNotEmpty;
    _driveLetter = hasDrive ? widget.availableDriveLetters.first : null;
    // When WinFsp is not installed the picker hides it; fall back to Cloud
    // Files so the selected value always reflects something mountable.
    final configuredEngine =
        widget.currentEngine ??
        (widget.showWindowsMountMode ? WindowsMountEngine.cloudFiles : null);
    _engine =
        (configuredEngine == WindowsMountEngine.winFsp &&
            !widget.winFspAvailable)
        ? WindowsMountEngine.cloudFiles
        : configuredEngine;
    if (_readOnly && widget.showWindowsMountMode) {
      _engine = WindowsMountEngine.winFsp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final requiresDriveLetter = _usesWinFsp;
    final usesPath = !requiresDriveLetter;
    return AppShadDialog(
      title: const Text('挂载存储桶'),
      description: Text('配置 ${widget.bucket} 的本地挂载。'),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadSwitch(
              value: _readOnly,
              onChanged: widget.forceReadOnly ? null : _setReadOnly,
              label: Text(
                '只读挂载',
                style: theme.textTheme.small.copyWith(
                  color: theme.colorScheme.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              sublabel: Text(
                widget.forceReadOnly
                    ? '该桶已由账号策略设为只读，不能在此修改。'
                    : '关闭时允许在挂载目录中新增、修改和删除文件。',
              ),
            ),
            if (widget.showWindowsMountMode && _readOnly) ...[
              const SizedBox(height: 8),
              Text(
                '严格只读会使用 WinFsp 虚拟文件系统，避免 Explorer 先写入本地缓存后才被拒绝。',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
            if (widget.showWindowsMountMode && _engine != null) ...[
              const SizedBox(height: 18),
              MountEnginePicker(
                theme: theme,
                engine: _engine!,
                winFspAvailable: widget.winFspAvailable,
                onChanged: _setEngine,
              ),
            ],
            if (widget.showWindowsMountMode && requiresDriveLetter) ...[
              const SizedBox(height: 18),
              _FieldLabel(text: '盘符', theme: theme),
              const SizedBox(height: 8),
              if (widget.availableDriveLetters.isNotEmpty)
                ShadSelect<String>(
                  key: ValueKey<String?>(_driveLetter),
                  minWidth: 440,
                  initialValue: _driveLetter,
                  ensureSelectedVisible: false,
                  selectedOptionBuilder: (context, value) => Text(value),
                  options: widget.availableDriveLetters
                      .map(
                        (letter) => ShadOption<String>(
                          value: letter,
                          child: Text(letter),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _driveLetter = value),
                )
              else
                Text(
                  'WinFsp 虚拟文件系统仅支持盘符挂载，请先释放一个可用盘符。',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
            ],
            if (widget.showWindowsMountMode && !requiresDriveLetter) ...[
              const SizedBox(height: 18),
              Text(
                'Cloud Files 使用本地同步目录。需要在资源管理器显示桶级容量时，请选择 WinFsp 虚拟文件系统并分配盘符。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
            if (!widget.showWindowsMountMode || usesPath) ...[
              const SizedBox(height: 16),
              _PathPicker(
                theme: theme,
                mountPath: _mountPath,
                onPick: _pickDirectory,
                onReset: _mountPath.isEmpty
                    ? null
                    : () => setState(() => _mountPath = ''),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  ShadButton.outline(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  ShadButton(
                    onPressed: _canSubmit
                        ? () => Navigator.of(context).pop(
                            MountBucketOptions(
                              mountPath: usesPath ? _mountPath : '',
                              readOnly: _readOnly,
                              driveLetter: usesPath ? '' : _driveLetter ?? '',
                              windowsMountEngine: widget.showWindowsMountMode
                                  ? _engine
                                  : null,
                            ),
                          )
                        : null,
                    child: const Text('开始挂载'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _usesWinFsp =>
      widget.showWindowsMountMode && _engine == WindowsMountEngine.winFsp;

  bool get _canSubmit => _usesWinFsp ? _driveLetter != null : true;

  void _setReadOnly(bool value) {
    setState(() {
      _readOnly = value;
      // Cloud Files receives post-operation callbacks and cannot veto an
      // Explorer write. WinFsp rejects the write itself with EROFS instead.
      if (value && widget.showWindowsMountMode) {
        _engine = WindowsMountEngine.winFsp;
      }
    });
  }

  void _setEngine(WindowsMountEngine value) {
    setState(() {
      // Do not silently downgrade a strict read-only mount to Cloud Files.
      _engine = _readOnly && value == WindowsMountEngine.cloudFiles
          ? WindowsMountEngine.winFsp
          : value;
    });
  }

  Future<void> _pickDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择挂载路径',
      initialDirectory: _mountPath.trim().isEmpty ? null : _mountPath.trim(),
    );
    if (path == null || path.trim().isEmpty || !mounted) return;
    setState(() => _mountPath = path.trim());
  }
}

class _PathPicker extends StatelessWidget {
  const _PathPicker({
    required this.theme,
    required this.mountPath,
    required this.onPick,
    required this.onReset,
  });

  final ShadThemeData theme;
  final String mountPath;
  final VoidCallback onPick;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final hasCustomPath = mountPath.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(text: '挂载路径', theme: theme),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            hasCustomPath ? mountPath : '使用系统默认挂载路径',
            style: TextStyle(
              fontSize: 12,
              color: hasCustomPath
                  ? theme.colorScheme.foreground
                  : theme.colorScheme.mutedForeground,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ShadButton.outline(onPressed: onPick, child: const Text('选择路径')),
            const SizedBox(width: 10),
            ShadButton.outline(onPressed: onReset, child: const Text('使用默认')),
          ],
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, required this.theme});

  final String text;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.foreground,
      ),
    );
  }
}

/// Confirms unmounting and makes Cloud Files cache retention an explicit choice.
class UnmountBucketChoice {
  const UnmountBucketChoice({required this.removeLocalCache});

  final bool removeLocalCache;
}

Future<UnmountBucketChoice?> showUnmountBucketDialog(
  BuildContext context, {
  required String bucket,
  required bool canRemoveLocalCache,
}) {
  var removeLocalCache = false;
  return showAppModal<UnmountBucketChoice?>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AppShadDialog(
        title: const Text('卸载存储桶'),
        description: Text('即将卸载 $bucket。'),
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('请先关闭正在从该挂载目录打开的文件。卸载后仍打开的文件可能继续引用本地缓存，后续修改不会自动同步。'),
              if (canRemoveLocalCache) ...[
                const SizedBox(height: 16),
                ShadSwitch(
                  value: removeLocalCache,
                  onChanged: (value) =>
                      setDialogState(() => removeLocalCache = value),
                  label: const Text('同时删除本地缓存'),
                  sublabel: const Text('仅删除默认 Cloud Files 同步目录中的本地副本，不影响云端文件。'),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ShadButton.outline(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('取消'),
                    ),
                    ShadButton(
                      onPressed: () => Navigator.of(dialogContext).pop(
                        UnmountBucketChoice(removeLocalCache: removeLocalCache),
                      ),
                      child: const Text('确认卸载'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
