// 远程目录选择器：弹出文件管理式的桶/目录浏览器。
// 第一级显示桶列表，进入桶后显示目录树，支持创建目录和选择当前目录。
// 选择后返回 (bucket, prefix, profileName, config) 四元组。
import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:remote_storage/widgets/whitesur_file_icon.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/services/desktop_overlay.dart';
import 'package:remote_storage/services/remote_directory_picker_window_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/services/app_modal.dart';

part 'remote_directory_picker_actions.dart';
part 'remote_directory_picker_list.dart';

/// 远程目录选择结果。
class RemoteDirectoryResult {
  const RemoteDirectoryResult({
    required this.bucket,
    required this.prefix,
    required this.profileName,
    required this.config,
  });

  final String bucket;
  final String prefix;
  final String profileName;
  final RemoteStorageConfig config;
}

/// 弹出远程目录选择器，返回选中的桶+目录前缀。
Future<RemoteDirectoryResult?> showRemoteDirectoryPicker({
  required BuildContext context,
  required RemoteStorageGateway api,
  required List<FileManagerBucketEntry> buckets,
  RemoteDirectoryResult? initial,
  double? anchorFrameLeft,
  double? anchorFrameTop,
  double? anchorFrameWidth,
  double? anchorFrameHeight,
  String? rootWindowId,
}) {
  return showDesktopOverlayOrDialog<RemoteDirectoryResult>(
    context: context,
    openSubWindow: () => RemoteDirectoryPickerWindowService.instance.openPicker(
      buckets: buckets,
      initial: initial,
      anchorFrameLeft: anchorFrameLeft,
      anchorFrameTop: anchorFrameTop,
      anchorFrameWidth: anchorFrameWidth,
      anchorFrameHeight: anchorFrameHeight,
      rootWindowId: rootWindowId,
    ),
    showDialog: () => showAppModal<RemoteDirectoryResult>(
      context: context,
      builder: (_) => RemoteDirectoryPickerDialog(
        api: api,
        buckets: buckets,
        initial: initial,
        asDialog: true,
      ),
    ),
  );
}

class RemoteDirectoryPickerDialog extends StatefulWidget {
  const RemoteDirectoryPickerDialog({
    super.key,
    required this.api,
    required this.buckets,
    this.initial,
    this.asDialog = true,
    this.onConfirm,
    this.onCancel,
  });

  final RemoteStorageGateway api;
  final List<FileManagerBucketEntry> buckets;
  final RemoteDirectoryResult? initial;

  /// true = 应用内拟态框（默认）；false = Debug 子窗口裸内容。
  final bool asDialog;
  final void Function(RemoteDirectoryResult result)? onConfirm;
  final VoidCallback? onCancel;

  @override
  State<RemoteDirectoryPickerDialog> createState() =>
      _RemoteDirectoryPickerDialogState();
}

class _RemoteDirectoryPickerDialogState
    extends State<RemoteDirectoryPickerDialog> {
  // null = 桶列表视图；非 null = 已进入该桶，浏览目录。
  FileManagerBucketEntry? _activeBucket;
  String _prefix = '';
  List<ObjectInfo> _objects = const [];
  bool _loading = false;
  String? _error;
  // Prevent a slower previous directory request from overwriting new navigation.
  int _loadGeneration = 0;

  // 创建目录弹窗状态。
  bool _showCreateDir = false;
  final _dirNameController = TextEditingController();

  /// 是否列出以 . 开头的隐藏文件（文件仍不可选，仅展示）。
  bool _showHiddenFiles = false;

  @override
  void initState() {
    super.initState();
    // 仅恢复仍然存在的精确目标，避免把空/过期目标的前缀套到第一个桶。
    final initial = widget.initial;
    if (initial != null) {
      for (final bucket in widget.buckets) {
        if (bucket.bucket.name != initial.bucket ||
            bucket.profileName != initial.profileName) {
          continue;
        }
        _activeBucket = bucket;
        _prefix = initial.prefix;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadObjects();
        });
        break;
      }
    }
  }

  @override
  void dispose() {
    _dirNameController.dispose();
    super.dispose();
  }

  /// 供 actions part 文件触发重建。
  void markDirty(VoidCallback fn) => setState(fn);

  /// 面包屑路径段：桶名 + 当前目录层级。
  List<String> get _breadcrumbs {
    if (_activeBucket == null) return [];
    final parts = <String>[_activeBucket!.label];
    if (_prefix.isNotEmpty) {
      parts.addAll(_prefix.split('/').where((s) => s.isNotEmpty));
    }
    return parts;
  }

  void _enterBucket(FileManagerBucketEntry entry) {
    setState(() {
      _activeBucket = entry;
      _prefix = '';
      _objects = const [];
      _error = null;
    });
    _loadObjects();
  }

  void _openDirectory(ObjectInfo obj) {
    setState(() {
      _prefix = obj.key;
      _loading = true;
      _error = null;
    });
    _loadObjects();
  }

  void _navigateToBreadcrumb(int index) {
    if (index == 0) {
      // 回到桶根目录。
      setState(() {
        _prefix = '';
        _loading = true;
      });
    } else {
      final parts = _prefix.split('/').where((s) => s.isNotEmpty).toList();
      setState(() {
        _prefix = parts.take(index).join('/');
        if (_prefix.isNotEmpty) _prefix += '/';
        _loading = true;
      });
    }
    _loadObjects();
  }

  void _goBackToBuckets() {
    setState(() {
      _loadGeneration++;
      _activeBucket = null;
      _prefix = '';
      _objects = const [];
      _error = null;
    });
  }

  void _confirm() {
    if (_activeBucket == null) return;
    final result = RemoteDirectoryResult(
      bucket: _activeBucket!.bucket.name,
      prefix: _prefix,
      profileName: _activeBucket!.profileName,
      config: _activeBucket!.config,
    );
    if (widget.onConfirm != null) {
      widget.onConfirm!(result);
      return;
    }
    Navigator.of(context).pop(result);
  }

  void _cancel() {
    if (widget.onCancel != null) {
      widget.onCancel!();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final body = SizedBox(
      width: double.infinity,
      height: widget.asDialog ? 480 : double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.asDialog) ...[
            Text(
              _activeBucket == null ? '选择一个存储桶进入。' : '浏览目录后点击「选择当前目录」确认。',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _buildBreadcrumbBar(theme),
          const SizedBox(height: 8),
          buildHiddenFilesToggle(theme),
          const SizedBox(height: 8),
          Expanded(child: _buildContent(theme)),
          const SizedBox(height: 12),
          buildCreateDirInput(theme),
          _buildActions(),
        ],
      ),
    );
    if (!widget.asDialog) return body;
    return ShadDialog(
      title: const Text('选择远端目录'),
      description: Text(
        _activeBucket == null ? '选择一个存储桶进入。' : '浏览目录后点击「选择当前目录」确认。',
      ),
      constraints: const BoxConstraints(maxWidth: 640),
      child: body,
    );
  }

  Widget _buildBreadcrumbBar(ShadThemeData theme) {
    if (_activeBucket == null) {
      return const SizedBox(height: 4);
    }
    final crumbs = _breadcrumbs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: theme.colorScheme.secondary),
      child: Row(
        children: [
          for (int i = 0; i < crumbs.length; i++) ...[
            if (i > 0) ...[
              Icon(
                LucideIcons.chevronRight,
                size: 12,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 4),
            ],
            GestureDetector(
              onTap: () => _navigateToBreadcrumb(i),
              child: Text(
                crumbs[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: i == crumbs.length - 1
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: i == crumbs.length - 1
                      ? theme.colorScheme.foreground
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(ShadThemeData theme) {
    if (_activeBucket == null) {
      return _buildBucketList(theme);
    }
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: 32,
              color: theme.colorScheme.destructive,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }
    return buildDirectoryList(theme);
  }

  Widget _buildBucketList(ShadThemeData theme) {
    if (widget.buckets.isEmpty) {
      return Center(
        child: Text(
          '没有可用的存储桶。',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: widget.buckets.length,
      itemBuilder: (context, i) {
        final entry = widget.buckets[i];
        return _bucketTile(theme, entry);
      },
    );
  }

  Widget _bucketTile(ShadThemeData theme, FileManagerBucketEntry entry) {
    return FileListTile(
      leading: const WhiteSurFileIcon(
        assetPath: 'assets/icons/whitesur/places/network-server-balanced.svg',
        size: 20,
      ),
      title: entry.label,
      sizeLabel: entry.sourceLabel,
      onTap: () => _enterBucket(entry),
      showDivider: false,
    );
  }

  // ".." 返回上一级导航。
  void _navigateUp() {
    if (_prefix.isEmpty) return;
    final parts = _prefix.split('/').where((s) => s.isNotEmpty).toList();
    setState(() {
      _prefix = parts.length <= 1
          ? ''
          : '${parts.take(parts.length - 1).join('/')}/';
    });
    _loadObjects();
  }

  Widget _dirTile(ShadThemeData theme, ObjectInfo obj) {
    final isParent = obj.key == '../';
    final name = isParent ? '..' : obj.displayName;
    return FileListTile(
      leading: isParent
          ? SizedBox.square(
              dimension: 20,
              child: Center(
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          : LocalCloudPanFileIcon(name: name, isDirectory: true, size: 20),
      title: name,
      sizeLabel: isParent ? '返回上一级' : '',
      onTap: () {
        if (isParent) {
          _navigateUp();
        } else {
          _openDirectory(obj);
        }
      },
      showDivider: false,
    );
  }
}
