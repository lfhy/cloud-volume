// 回收站设置区：负责编辑桶级软删除目录名称与自动清理保留期。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class TrashSettingsSection extends StatefulWidget {
  const TrashSettingsSection({
    super.key,
    required this.theme,
    required this.directoryName,
    required this.autoCleanupEnabled,
    required this.retentionDays,
    required this.saving,
    required this.errorText,
    required this.onSave,
  });

  final ShadThemeData theme;
  final String directoryName;
  final bool autoCleanupEnabled;
  final int retentionDays;
  final bool saving;
  final String? errorText;
  final Future<void> Function(
    String directoryName,
    bool autoCleanupEnabled,
    int retentionDays,
  )
  onSave;

  @override
  State<TrashSettingsSection> createState() => _TrashSettingsSectionState();
}

class _TrashSettingsSectionState extends State<TrashSettingsSection> {
  late final TextEditingController _directoryController;
  late final TextEditingController _retentionController;
  late bool _autoCleanupEnabled;

  @override
  void initState() {
    super.initState();
    _directoryController = TextEditingController(text: widget.directoryName);
    _autoCleanupEnabled = widget.autoCleanupEnabled;
    _retentionController = TextEditingController(
      text: widget.retentionDays.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant TrashSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directoryName != widget.directoryName) {
      _directoryController.text = widget.directoryName;
    }
    if (oldWidget.autoCleanupEnabled != widget.autoCleanupEnabled) {
      _autoCleanupEnabled = widget.autoCleanupEnabled;
    }
    if (oldWidget.retentionDays != widget.retentionDays) {
      _retentionController.text = widget.retentionDays.toString();
    }
  }

  @override
  void dispose() {
    _directoryController.dispose();
    _retentionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '删除对象时会先移入回收站目录。关闭自动清理时只保留回收站内容；开启后会按你设置的保留天数自动清理。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        _buildLabel(theme, '回收站目录名称'),
        const SizedBox(height: 6),
        ShadInput(
          controller: _directoryController,
          enabled: !widget.saving,
          placeholder: const Text('.trash'),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '启用自动清理',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _autoCleanupEnabled
                          ? '当前会按保留天数自动清理回收站'
                          : '当前只保留回收站内容，不自动清理',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              ShadSwitch(
                value: _autoCleanupEnabled,
                onChanged: widget.saving
                    ? null
                    : (value) {
                        setState(() => _autoCleanupEnabled = value);
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildLabel(theme, '自动清理保留天数'),
        const SizedBox(height: 6),
        ShadInput(
          controller: _retentionController,
          enabled: !widget.saving && _autoCleanupEnabled,
          keyboardType: TextInputType.number,
          placeholder: const Text('30'),
        ),
        const SizedBox(height: 10),
        Text(
          _autoCleanupEnabled
              ? '默认 30 天；保存后会按当前保留天数执行后台清理。'
              : '关闭后不会自动删除回收站内容，需要你手动清理或恢复。',
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            widget.errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
        const SizedBox(height: 12),
        ShadButton(
          onPressed: widget.saving
              ? null
              : () => widget.onSave(
                  _directoryController.text.trim(),
                  _autoCleanupEnabled,
                  int.tryParse(_retentionController.text.trim()) ?? 30,
                ),
          child: Text(widget.saving ? '保存中...' : '保存回收站设置'),
        ),
      ],
    );
  }

  Widget _buildLabel(ShadThemeData theme, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.foreground,
      ),
    );
  }
}
