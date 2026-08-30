// 文件同步配置编辑弹窗：分步选择同步两端、策略与高级设置。
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/models/sync_remote_open_request.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/widgets/sync_directory_open_buttons.dart';
import 'package:remote_storage/services/sync_directory_navigation.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:window_manager/window_manager.dart';

part 'file_sync_profile_editor_steps.dart';

class FileSyncProfileEditor extends StatefulWidget {
  const FileSyncProfileEditor({
    super.key,
    required this.api,
    required this.buckets,
    required this.onSave,
    this.initial,
    this.onSaved,
    this.asDialog = true,
    this.creatorWindowId,
    this.anchorFrameLeft,
    this.anchorFrameTop,
    this.anchorFrameWidth,
    this.anchorFrameHeight,
  });

  final RemoteStorageGateway api;

  /// 文件管理页加载的桶列表，供目录选择器使用。
  final List<FileManagerBucketEntry> buckets;
  final Future<bool> Function(SyncProfile profile) onSave;

  /// 保存成功后回调（子窗口用，关闭窗口）。
  final VoidCallback? onSaved;

  /// true = 应用内拟态框（默认）；false = Debug 子窗口裸内容。
  final bool asDialog;

  /// 子窗口相对此父引擎窗口居中（desktop_multi_window id）。
  final String? creatorWindowId;
  final double? anchorFrameLeft;
  final double? anchorFrameTop;
  final double? anchorFrameWidth;
  final double? anchorFrameHeight;

  final SyncProfile? initial;

  @override
  State<FileSyncProfileEditor> createState() => _FileSyncProfileEditorState();
}

class _FileSyncProfileEditorState extends State<FileSyncProfileEditor> {
  final _nameController = TextEditingController();
  final _localPathController = TextEditingController();
  final _excludeController = TextEditingController();
  final _nameFocusNode = FocusNode(), _excludeFocusNode = FocusNode();

  // 当前步骤索引（0 = 选择桶，1 = 同步设置）。
  int _step = 0;
  RemoteDirectoryResult? _remoteDir;
  SyncDirection _direction = SyncDirection.twoway;
  SyncConflictPolicy _conflictPolicy = SyncConflictPolicy.newest;
  int _intervalSeconds = 300;
  int _quietSeconds = 10;
  bool _enabled = true;
  bool _saving = false;
  String? _errorText;

  static const _stepLabels = ['同步两端', '同步策略', '高级设置'];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _nameController.text = initial.name;
    _localPathController.text = initial.localPath;
    _direction = initial.direction;
    _conflictPolicy = initial.conflictPolicy;
    _intervalSeconds = initial.intervalSeconds;
    _quietSeconds = initial.quietSeconds;
    _excludeController.text = initial.excludePatterns.join('\n');
    _enabled = initial.enabled;
    // 编辑时回填远端目录选择结果。
    _remoteDir = RemoteDirectoryResult(
      bucket: initial.bucket,
      prefix: initial.remotePrefix,
      profileName: initial.accountProfile,
      config:
          widget.buckets
              .where(
                (b) =>
                    b.bucket.name == initial.bucket &&
                    b.profileName == initial.accountProfile,
              )
              .firstOrNull
              ?.config ??
          widget.buckets.first.config,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _localPathController.dispose();
    _excludeController.dispose();
    _nameFocusNode.dispose();
    _excludeFocusNode.dispose();
    super.dispose();
  }

  /// 供 steps 顶层函数触发重建。
  void markDirty(VoidCallback fn) => setState(fn);

  /// 保存前必须完成「同步两端」：本地目录 + 远端目录（任意步骤点保存都会校验）。
  bool _validateEndpoints({bool jumpToEndpointsStep = false}) {
    if (_localPathController.text.trim().isEmpty) {
      setState(() {
        _errorText = '请先在「同步两端」中选择本地目录';
        if (jumpToEndpointsStep) _step = 0;
      });
      if (jumpToEndpointsStep) _applySubWindowStepSize();
      return false;
    }
    if (_remoteDir == null) {
      setState(() {
        _errorText = '请先在「同步两端」中选择远端目录';
        if (jumpToEndpointsStep) _step = 0;
      });
      if (jumpToEndpointsStep) _applySubWindowStepSize();
      return false;
    }
    return true;
  }

  bool _validateCurrentStep() {
    setState(() => _errorText = null);
    if (_step == 0) {
      return _validateEndpoints();
    }
    return true;
  }

  static const _subWindowSizeStep0 = Size(600, 480);
  static const _subWindowSizeStep1 = Size(600, 500);
  static const _subWindowSizeStep2 = Size(600, 480);

  Future<void> _applySubWindowStepSize() async {
    if (widget.asDialog) return;
    final size = switch (_step) {
      0 => _subWindowSizeStep0,
      1 => _subWindowSizeStep1,
      _ => _subWindowSizeStep2,
    };
    try {
      await resizeKeepingWindowCenter(size);
      await windowManager.focus();
    } catch (_) {}
  }

  void _next() {
    if (_step < _stepLabels.length - 1) {
      if (!_validateCurrentStep()) return;
      setState(() => _step++);
      _applySubWindowStepSize();
      return;
    }
    if (!_validateEndpoints(jumpToEndpointsStep: true)) return;
    _submit();
  }

  void _back() {
    _goToStep(_step - 1);
  }

  /// 步骤选项卡：可自由切换查看，不在此处校验（仅「下一步/保存」时校验）。
  void _goToStep(int index) {
    if (index < 0 || index >= _stepLabels.length || index == _step) return;
    setState(() {
      _errorText = null;
      _step = index;
    });
    _applySubWindowStepSize();
  }

  Future<void> _pickLocalDirectory() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择需要同步的本地目录');
    if (path != null) {
      setState(() => _localPathController.text = path);
    }
  }

  // 弹出远程目录选择器，选择桶和目录前缀。
  Future<void> _openLocalDirectoryInShell() async {
    final path = _localPathController.text.trim();
    if (path.isEmpty) return;
    await SyncDirectoryOpenButtons.openLocal(context, path);
  }

  Future<void> _openRemoteSyncDirectory() async {
    final remote = _remoteDir;
    if (remote == null) return;
    final request = SyncRemoteOpenRequest(
      profileName: remote.profileName,
      bucket: remote.bucket,
      remotePrefix: remote.prefix,
    );
    if (widget.asDialog) {
      SyncDirectoryNavigation.instance.openRemote(request);
      return;
    }
    await SyncDirectoryOpenButtons.openRemoteViaParentWindow(
      context,
      creatorWindowId: widget.creatorWindowId,
      request: request,
    );
  }

  Future<void> _pickRemoteDirectory() async {
    final result = await showRemoteDirectoryPicker(
      context: context,
      api: widget.api,
      buckets: widget.buckets,
      initial: _remoteDir,
      anchorFrameLeft: widget.anchorFrameLeft,
      anchorFrameTop: widget.anchorFrameTop,
      anchorFrameWidth: widget.anchorFrameWidth,
      anchorFrameHeight: widget.anchorFrameHeight,
      rootWindowId: widget.creatorWindowId,
    );
    if (result != null) {
      setState(() => _remoteDir = result);
    }
  }

  Future<void> _submit() async {
    if (!_validateEndpoints(jumpToEndpointsStep: true)) return;
    final remote = _remoteDir;
    if (remote == null) return;
    // 名称留空时用桶名做默认值。
    final name = _nameController.text.trim().isEmpty
        ? remote.bucket
        : _nameController.text.trim();
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final profile =
        (widget.initial ??
                SyncProfile(
                  id: '',
                  name: '',
                  accountProfile: '',
                  bucket: '',
                  remotePrefix: '',
                  localPath: '',
                  direction: SyncDirection.twoway,
                  intervalSeconds: 300,
                  conflictPolicy: SyncConflictPolicy.newest,
                  excludePatterns: const <String>[],
                  quietSeconds: 10,
                  enabled: true,
                ))
            .copyWith(
              name: name,
              // 从目录选择器结果自动绑定。
              accountProfile: remote.profileName,
              bucket: remote.bucket,
              remotePrefix: remote.prefix,
              localPath: _localPathController.text.trim(),
              direction: _direction,
              intervalSeconds: _intervalSeconds,
              conflictPolicy: _conflictPolicy,
              quietSeconds: _quietSeconds,
              excludePatterns: _excludeController.text
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList(),
              enabled: _enabled,
            );
    final ok = await widget.onSave(profile);
    if (!mounted) return;
    if (ok) {
      widget.onSaved?.call();
      // 拟态框模式才 pop；子窗口由 onSaved 关闭 OS 窗口。
      if (mounted && widget.asDialog) Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _errorText = '保存失败，请检查配置';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (!widget.asDialog) {
      return _buildFillHeightLayout(theme);
    }
    final androidSheet = usesAndroidAppModalSheet;
    final compactAndroidSheet = usesCompactAndroidAppModalSheet(context);
    return AppShadDialog(
      title: Text(widget.initial == null ? '新建同步配置' : '编辑同步配置'),
      description: const Text('将一个本地目录与远端桶目录保持同步。'),
      constraints: const BoxConstraints(maxWidth: 600),
      androidFillHeight: androidSheet,
      scrollable: !androidSheet || compactAndroidSheet,
      child: androidSheet && !compactAndroidSheet
          ? _buildFillHeightLayout(theme)
          : _buildDialogContent(theme),
    );
  }

  /// Normal fill-height shells keep navigation pinned below the scrolling step.
  Widget _buildFillHeightLayout(ShadThemeData theme) {
    final stepBody = _buildStepBody(theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(theme),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Align(alignment: Alignment.topLeft, child: stepBody),
          ),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
        const SizedBox(height: 24),
        _buildNavButtons(theme),
      ],
    );
  }

  Widget _buildDialogContent(ShadThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(theme),
        const SizedBox(height: 20),
        _buildStepBody(theme),
        if (_errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
        const SizedBox(height: 24),
        _buildNavButtons(theme),
      ],
    );
  }

  Widget _buildStepBody(ShadThemeData theme) {
    return switch (_step) {
      0 => stepPickEndpoints(theme: theme, self: this),
      1 => stepSyncStrategy(theme: theme, self: this),
      _ => stepAdvancedSettings(theme: theme, self: this),
    };
  }

  /// 步骤选项卡：点击 1/2 可自由切换查看各步内容。
  Widget _buildStepIndicator(ShadThemeData theme) {
    return Row(
      children: List.generate(_stepLabels.length, (i) {
        final isActive = i == _step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _stepLabels.length - 1 ? 8 : 0),
            child: _buildStepTab(theme, i, isActive),
          ),
        );
      }),
    );
  }

  Widget _buildStepTab(ShadThemeData theme, int index, bool isActive) {
    final borderColor = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.border.withValues(alpha: 0.7);
    final bg = isActive
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.secondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _goToStep(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: isActive ? 1.5 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _stepLabels[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部导航。
  Widget _buildNavButtons(ShadThemeData theme) {
    final isLast = _step == _stepLabels.length - 1;
    return _syncDialogActionWrap([
      if (_step > 0) ...[
        ShadButton.outline(
          onPressed: _back,
          child: const Row(
            children: [
              Icon(LucideIcons.chevronLeft, size: 16),
              SizedBox(width: 2),
              Text('上一步'),
            ],
          ),
        ),
      ],
      ShadButton(
        onPressed: _saving ? null : _next,
        child: _saving
            ? const Text('保存中...')
            : Row(
                children: [
                  Text(isLast ? '保存' : '下一步'),
                  if (!isLast) ...[
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.chevronRight, size: 16),
                  ],
                ],
              ),
      ),
    ]);
  }
}
