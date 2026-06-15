// 同步设置组件集中展示挂载写回等待时间，避免通用设置页继续膨胀。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class WritebackQuietSecondsSection extends StatelessWidget {
  const WritebackQuietSecondsSection({
    super.key,
    required this.theme,
    required this.seconds,
    required this.saving,
    required this.errorText,
    required this.onChanged,
  });

  static const List<int> _options = <int>[3, 5, 10, 15, 30, 60, 120, 300];

  final ShadThemeData theme;
  final int seconds;
  final bool saving;
  final String? errorText;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final normalizedSeconds = seconds > 0 ? seconds : 10;
    final options = <int>{..._options, normalizedSeconds}.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '挂载目录里的文件写入后，会等待文件保持静止一段时间再推送到远端。时间越短越快同步，时间越长越适合连续保存的大文件。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ShadSelect<int>(
            key: ValueKey<int>(normalizedSeconds),
            minWidth: 220,
            initialValue: normalizedSeconds,
            placeholder: Text(_label(normalizedSeconds)),
            selectedOptionBuilder: (context, selected) =>
                Text(_label(selected)),
            options: options
                .map(
                  (item) =>
                      ShadOption<int>(value: item, child: Text(_label(item))),
                )
                .toList(growable: false),
            onChanged: saving
                ? null
                : (value) {
                    if (value != null) {
                      onChanged(value);
                    }
                  },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '默认 10 秒；已有挂载建议重新挂载后确保全部后台队列使用新配置。',
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }

  static String _label(int seconds) {
    if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      return '$minutes 分钟';
    }
    return '$seconds 秒';
  }
}

class MountMetadataCacheSection extends StatelessWidget {
  const MountMetadataCacheSection({
    super.key,
    required this.theme,
    required this.enabled,
    required this.seconds,
    required this.saving,
    required this.errorText,
    required this.onEnabledChanged,
    required this.onSecondsChanged,
  });

  static const List<int> _options = <int>[5, 10, 15, 30, 60, 120, 300, 600];

  final ShadThemeData theme;
  final bool enabled;
  final int seconds;
  final bool saving;
  final String? errorText;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onSecondsChanged;

  @override
  Widget build(BuildContext context) {
    final normalizedSeconds = seconds > 0 ? seconds : 60;
    final options = <int>{..._options, normalizedSeconds}.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '挂载浏览目录、读取文件信息时，可以先复用一段时间内的远端元数据，减少频繁请求。关闭后每次都会直接请求远端，适合需要最强实时性的场景。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
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
                      '启用元数据缓存',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enabled ? '当前会短暂复用远端元数据' : '当前每次都直接请求远端',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              ShadSwitch(
                value: enabled,
                onChanged: saving ? null : onEnabledChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ShadSelect<int>(
            key: ValueKey<String>('metadata-cache-$normalizedSeconds-$enabled'),
            minWidth: 220,
            initialValue: normalizedSeconds,
            placeholder: Text(_label(normalizedSeconds)),
            selectedOptionBuilder: (context, selected) =>
                Text(_label(selected)),
            options: options
                .map(
                  (item) =>
                      ShadOption<int>(value: item, child: Text(_label(item))),
                )
                .toList(growable: false),
            onChanged: !enabled || saving
                ? null
                : (value) {
                    if (value != null) {
                      onSecondsChanged(value);
                    }
                  },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '默认 1 分钟；修改后建议重新挂载，让新的缓存策略完整作用到当前会话。',
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }

  static String _label(int seconds) {
    if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      return '$minutes 分钟';
    }
    return '$seconds 秒';
  }
}
