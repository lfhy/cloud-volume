// Windows settings sections keep mount-specific controls out of the shared settings widget file.
import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class WindowsMountModeSection extends StatelessWidget {
  const WindowsMountModeSection({
    super.key,
    required this.theme,
    required this.mode,
    required this.saving,
    required this.errorText,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final WindowsMountMode mode;
  final bool saving;
  final String? errorText;
  final ValueChanged<WindowsMountMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Windows 可以在两种 Cloud Files 读路径和一个纯 WebDAV 回退模式之间切换。切换后请重新挂载 bucket 再验证效果。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ShadSelect<WindowsMountMode>(
            key: ValueKey<WindowsMountMode>(mode),
            minWidth: 320,
            initialValue: mode,
            placeholder: Text(_mountModeLabel(mode)),
            selectedOptionBuilder: (context, selected) =>
                Text(_mountModeLabel(selected)),
            options: WindowsMountMode.values
                .map(
                  (item) => ShadOption<WindowsMountMode>(
                    value: item,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_mountModeLabel(item)),
                        const SizedBox(height: 2),
                        Text(
                          _mountModeDescription(item),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: saving ? null : onChanged,
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

  static String _mountModeLabel(WindowsMountMode mode) {
    return switch (mode) {
      WindowsMountMode.cloudFilesCached => 'Cloud Files + 本地缓存/异步同步',
      WindowsMountMode.cloudFilesDirect => 'Cloud Files + 直连 S3',
      WindowsMountMode.webdav => '纯 WebDAV 映射盘',
    };
  }

  static String _mountModeDescription(WindowsMountMode mode) {
    return switch (mode) {
      WindowsMountMode.cloudFilesCached =>
        '使用 Cloud Files 外壳，但文件读写回到现有缓存、下载任务和异步写回链路。',
      WindowsMountMode.cloudFilesDirect =>
        '使用 Cloud Files 外壳，按需读取时直接请求远端对象，便于对比直连效果。',
      WindowsMountMode.webdav => '保留旧的映射盘回退模式，便于兼容性排查。',
    };
  }
}

class WindowsThisPcEntrySection extends StatelessWidget {
  const WindowsThisPcEntrySection({
    super.key,
    required this.theme,
    required this.enabled,
    required this.saving,
    required this.errorText,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final bool enabled;
  final bool saving;
  final String? errorText;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '关闭后，Windows 不会再在“此电脑”里创建 `云卷-xxx` 的入口，但挂载本身仍然可用。下次重新挂载后生效。',
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
                      '在“此电脑”中显示云卷入口',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enabled ? '当前会创建入口' : '当前不会创建入口',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              ShadSwitch(value: enabled, onChanged: saving ? null : onChanged),
            ],
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
}

class WindowsWritebackConcurrencySection extends StatelessWidget {
  const WindowsWritebackConcurrencySection({
    super.key,
    required this.theme,
    required this.concurrency,
    required this.saving,
    required this.errorText,
    required this.onChanged,
  });

  static const List<int> _options = <int>[1, 2, 4, 6, 8, 12, 16, 24, 32];

  final ShadThemeData theme;
  final int concurrency;
  final bool saving;
  final String? errorText;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '限制挂载写回同时上传的文件数，避免大批量复制时一下子并发几十上百个上传把 UI、网络和对象存储都打满。修改后请重新挂载 bucket 再生效。',
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
            key: ValueKey<int>(concurrency),
            minWidth: 220,
            initialValue: concurrency,
            placeholder: Text('$concurrency 个并发上传'),
            selectedOptionBuilder: (context, selected) =>
                Text('$selected 个并发上传'),
            options: _options
                .map(
                  (item) =>
                      ShadOption<int>(value: item, child: Text('$item 个并发上传')),
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
          '建议从 2 到 8 开始。目录树很大、单文件又不大的场景，值越大越容易把任务队列和后端压力同时放大。',
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
}

class WindowsMountRecoverySection extends StatelessWidget {
  const WindowsMountRecoverySection({
    super.key,
    required this.theme,
    required this.busy,
    required this.cleaningProcesses,
    required this.errorText,
    required this.onReset,
    required this.onCleanupProcesses,
  });

  final ShadThemeData theme;
  final bool busy;
  final bool cleaningProcesses;
  final String? errorText;
  final VoidCallback onReset;
  final VoidCallback onCleanupProcesses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '当 Cloud Files 或 WebDAV 挂载状态卡住时，这个兜底操作会强制清理当前挂载、残留 sync root 和前端挂载状态，方便重新验证挂载与写入流程。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '强制卸载并重置挂载状态',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '会调用底层 cleanup_mounts，对当前 bucket 挂载、旧 sync root、This PC 入口和本地挂载状态做一次兜底清理。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
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
        const SizedBox(height: 12),
        ShadButton.outline(
          onPressed: cleaningProcesses ? null : onCleanupProcesses,
          child: Text(cleaningProcesses ? '正在结束残留进程...' : '结束残留占用进程'),
        ),
        const SizedBox(height: 10),
        ShadButton.destructive(
          onPressed: busy ? null : onReset,
          child: Text(busy ? '正在重置...' : '强制卸载并重置状态'),
        ),
      ],
    );
  }
}
