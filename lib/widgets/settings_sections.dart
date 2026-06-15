// 设置页分区组件：下载目录、显示选项、缓存清理与主题色选项。

import 'package:flutter/material.dart';
import 'package:remote_storage/services/file_cache_store.dart';
import 'package:remote_storage/services/local_file_opener.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DownloadDirectorySection extends StatelessWidget {
  const DownloadDirectorySection({
    super.key,
    required this.theme,
    required this.configuredPath,
    required this.saving,
    required this.errorText,
    required this.onPickDirectory,
    required this.onResetDirectory,
  });

  final ShadThemeData theme;
  final String configuredPath;
  final bool saving;
  final String? errorText;
  final VoidCallback onPickDirectory;
  final VoidCallback onResetDirectory;

  @override
  Widget build(BuildContext context) {
    final hasConfiguredPath = configuredPath.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '下载文件时，保存对话框会优先打开到这个目录；未配置时自动退回系统下载目录。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            hasConfiguredPath ? configuredPath : '系统默认下载目录',
            style: TextStyle(
              fontSize: 12,
              color: hasConfiguredPath
                  ? theme.colorScheme.foreground
                  : theme.colorScheme.mutedForeground,
            ),
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
        Row(
          children: [
            ShadButton(
              onPressed: saving ? null : onPickDirectory,
              child: Text(saving ? '保存中...' : '选择目录'),
            ),
            const SizedBox(width: 10),
            ShadButton.outline(
              onPressed: saving || !hasConfiguredPath ? null : onResetDirectory,
              child: const Text('恢复默认'),
            ),
          ],
        ),
      ],
    );
  }
}

class VisibilitySection extends StatelessWidget {
  const VisibilitySection({
    super.key,
    required this.theme,
    required this.hideDotFiles,
    required this.saving,
    required this.errorText,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final bool hideDotFiles;
  final bool saving;
  final String? errorText;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '默认隐藏以 . 开头的目录和文件，便于像 macOS Finder 一样保持文件视图整洁。',
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
                      '隐藏点文件与点目录',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hideDotFiles ? '当前为默认隐藏' : '当前显示全部文件',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              ShadSwitch(
                value: hideDotFiles,
                onChanged: saving ? null : onChanged,
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
      ],
    );
  }
}

class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final controller = ThemeController.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '主题色',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in AccentPreset.values)
              ThemeOption(
                preset: preset,
                isSelected: controller.accent == preset,
                onTap: () => controller.onAccentChanged(preset),
              ),
          ],
        ),
      ],
    );
  }
}

class ThemeOption extends StatelessWidget {
  const ThemeOption({
    super.key,
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final AccentPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? preset.color.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: preset.color.withValues(alpha: 0.3))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: preset.color,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: preset.color.withValues(alpha: 0.25),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              preset.label,
              style: TextStyle(fontSize: 12, color: preset.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// 缓存清理组件：显示本地文件缓存统计并提供一键清理按钮。
class CacheCleanupSection extends StatefulWidget {
  const CacheCleanupSection({
    super.key,
    required this.theme,
    required this.onClearMountCache,
  });

  final ShadThemeData theme;
  final Future<int> Function() onClearMountCache;

  @override
  State<CacheCleanupSection> createState() => _CacheCleanupSectionState();
}

class _CacheCleanupSectionState extends State<CacheCleanupSection> {
  final FileCacheStore _cacheStore = FileCacheStore.instance;
  CacheStats? _stats;
  bool _loadingStats = false;
  bool _clearing = false;
  bool _openingDir = false;
  String? _resultMessage;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final stats = await _cacheStore.getCacheStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loadingStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStats = false);
    }
  }

  Future<void> _clearAllCache() async {
    setState(() {
      _clearing = true;
      _resultMessage = null;
    });
    try {
      final deletedCount = await _cacheStore.clearAllCache();
      final mountRemoved = await widget.onClearMountCache();
      if (!mounted) return;

      final parts = <String>['已清理 $deletedCount 个下载缓存文件'];
      if (mountRemoved > 0) {
        parts.add('$mountRemoved 个挂载缓存文件');
      }
      setState(() {
        _clearing = false;
        _resultMessage = '${parts.join('、')}。';
        _stats = const CacheStats(count: 0, totalBytes: 0);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _resultMessage = '清理失败：$error';
      });
    }
  }

  Future<void> _openCacheDir() async {
    setState(() => _openingDir = true);
    try {
      final cachePath = await _cacheStore.getCacheDirectoryPath();
      await LocalFileOpener.openPath(cachePath);
    } catch (error) {
      if (!mounted) return;
      setState(() => _resultMessage = '打开缓存目录失败：$error');
    } finally {
      if (mounted) setState(() => _openingDir = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '上传和打开文件时会在本地产生缓存文件。这些缓存不会自动删除，'
          '长期使用可能占用较多磁盘空间。点击下方按钮可手动清理所有本地缓存。',
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
                      '本地缓存',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_loadingStats)
                      Text(
                        '正在计算...',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      )
                    else if (_stats != null)
                      Text(
                        _stats!.count == 0
                            ? '当前没有缓存文件'
                            : '${_stats!.count} 个文件，共 ${_stats!.formattedSize}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: _loadingStats ? null : _loadStats,
                    child: Icon(
                      LucideIcons.refreshCw,
                      size: 14,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 4),
                  ShadButton.outline(
                    onPressed:
                        (_clearing || _loadingStats || (_stats?.count ?? 0) == 0)
                            ? null
                            : _clearAllCache,
                    child: Text(_clearing ? '清理中...' : '清理缓存'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_resultMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _resultMessage!,
            style: TextStyle(
              fontSize: 12,
              color: _resultMessage!.startsWith('清理失败')
                  ? theme.colorScheme.destructive
                  : theme.colorScheme.mutedForeground,
            ),
          ),
        ],
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _openingDir ? null : _openCacheDir,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.folderOpen,
                size: 13,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 6),
              Text(
                _openingDir ? '正在打开...' : '打开缓存文件夹',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.mutedForeground,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
