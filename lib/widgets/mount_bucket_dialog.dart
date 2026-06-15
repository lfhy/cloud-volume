// 挂载设置弹窗：选择挂载路径和读写模式，保持桶列表操作行简洁。
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Future<MountBucketOptions?> showMountBucketDialog(
  BuildContext context, {
  required String bucket,
}) {
  return showShadDialog<MountBucketOptions?>(
    context: context,
    builder: (dialogContext) => _MountBucketDialog(bucket: bucket),
  );
}

class _MountBucketDialog extends StatefulWidget {
  const _MountBucketDialog({required this.bucket});

  final String bucket;

  @override
  State<_MountBucketDialog> createState() => _MountBucketDialogState();
}

class _MountBucketDialogState extends State<_MountBucketDialog> {
  String _mountPath = '';
  bool _readOnly = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final hasCustomPath = _mountPath.trim().isNotEmpty;
    return ShadDialog(
      title: const Text('挂载存储桶'),
      description: Text('选择 ${widget.bucket} 的本地挂载方式。'),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeSwitch(
              readOnly: _readOnly,
              onChanged: (value) => setState(() => _readOnly = value),
            ),
            const SizedBox(height: 16),
            Text(
              '挂载路径',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                hasCustomPath ? _mountPath : '使用系统默认挂载路径',
                style: TextStyle(
                  fontSize: 12,
                  color: hasCustomPath
                      ? theme.colorScheme.foreground
                      : theme.colorScheme.mutedForeground,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ShadButton.outline(
                  onPressed: _pickDirectory,
                  child: const Text('选择路径'),
                ),
                const SizedBox(width: 10),
                ShadButton.outline(
                  onPressed: hasCustomPath
                      ? () => setState(() => _mountPath = '')
                      : null,
                  child: const Text('使用默认'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 10),
                ShadButton(
                  onPressed: () => Navigator.of(context).pop(
                    MountBucketOptions(
                      mountPath: _mountPath,
                      readOnly: _readOnly,
                    ),
                  ),
                  child: const Text('开始挂载'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择挂载路径',
      initialDirectory: _mountPath.trim().isEmpty ? null : _mountPath.trim(),
    );
    if (path == null || path.trim().isEmpty) {
      return;
    }
    setState(() => _mountPath = path.trim());
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.readOnly, required this.onChanged});

  final bool readOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: ShadButton(
            size: ShadButtonSize.sm,
            onPressed: () => onChanged(false),
            backgroundColor: readOnly
                ? theme.colorScheme.secondary
                : theme.colorScheme.primary,
            foregroundColor: readOnly
                ? theme.colorScheme.foreground
                : theme.colorScheme.primaryForeground,
            child: const Text('读写挂载'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ShadButton(
            size: ShadButtonSize.sm,
            onPressed: () => onChanged(true),
            backgroundColor: readOnly
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
            foregroundColor: readOnly
                ? theme.colorScheme.primaryForeground
                : theme.colorScheme.foreground,
            child: const Text('只读挂载'),
          ),
        ),
      ],
    );
  }
}
