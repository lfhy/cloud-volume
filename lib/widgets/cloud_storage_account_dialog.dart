// 账号弹窗：新增使用连接/桶向导，编辑保持单页；字段组件拆至 part 文件。
// Debug 子窗口按内容自适应，默认使用应用内 ShadDialog。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/cloud_storage_account_draft.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/utils/account_config_builder.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/account_proxy_section.dart';
import 'package:remote_storage/widgets/baidu_pan_auth_section.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';
import 'package:remote_storage/widgets/measure_size.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

export 'package:remote_storage/models/cloud_storage_account_draft.dart';

part 'cloud_storage_account_dialog_steps.dart';
part 'cloud_storage_account_dialog_bucket_visibility.dart';
part 'cloud_storage_account_dialog_bucket_loading.dart';
part 'cloud_storage_account_dialog_credentials.dart';
part 'cloud_storage_account_dialog_fields.dart';
part 'cloud_storage_account_dialog_oauth.dart';

/// 账号管理页使用的新增/编辑账号对话框。
/// 保存时返回 [RemoteStorageConfig] 给调用方，由调用方决定 profileName 并保存。
class CloudStorageAccountDialog extends StatefulWidget {
  const CloudStorageAccountDialog({
    super.key,
    required this.onSave,
    required this.onStartBaiduPanAuthorization,
    required this.onAuthorizeBaiduPan,
    required this.onListBuckets,
    required this.api,
    this.initialConfig,
    this.editing = false,
    this.asDialog = true,
    this.simpleMode = false,
    this.onSaved,
    this.onCancel,
    this.creatorWindowId,
    this.creatorFrameLeft,
    this.creatorFrameTop,
    this.creatorFrameWidth,
    this.creatorFrameHeight,
  });

  final Future<bool> Function(RemoteStorageConfig config) onSave;
  final Future<String> Function() onStartBaiduPanAuthorization;
  final Future<RemoteStorageConfig> Function(String displayName, String code)
  onAuthorizeBaiduPan;
  final Future<List<BucketInfo>> Function(RemoteStorageConfig config)
  onListBuckets;
  final RemoteStorageGateway api;
  final RemoteStorageConfig? initialConfig;
  final bool editing;

  /// true = 应用内拟态框（默认）；false = Debug 子窗口裸内容。
  final bool asDialog;

  /// Lightweight mode for backup-only storage: skips name/mapped-bucket fields
  /// and the bucket-visibility step. After protocol + connection fields the
  /// config is returned directly so the caller can handle bucket selection.
  final bool simpleMode;

  /// 子窗口模式保存成功后回调（关闭窗口）。
  final VoidCallback? onSaved;

  /// 子窗口模式取消时回调。
  final VoidCallback? onCancel;

  /// Parent frame for re-centering after content-fit resize (sub-window only).
  final String? creatorWindowId;
  final double? creatorFrameLeft;
  final double? creatorFrameTop;
  final double? creatorFrameWidth;
  final double? creatorFrameHeight;

  @override
  State<CloudStorageAccountDialog> createState() =>
      _CloudStorageAccountDialogState();
}

class _CloudStorageAccountDialogState extends State<CloudStorageAccountDialog> {
  StorageType _storageType = StorageType.s3;
  final _nameController = TextEditingController();
  final _mappedBucketNameController = TextEditingController();
  final _endpointController = TextEditingController();
  final _regionController = TextEditingController(text: 'auto');
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _webdavUsernameController = TextEditingController();
  final _webdavPasswordController = TextEditingController();
  final _ftpUsernameController = TextEditingController();
  final _ftpPasswordController = TextEditingController();
  final _ftpPortController = TextEditingController();
  bool _ftpAnonymous = false;
  final _baiduAuthCodeController = TextEditingController();
  final _proxyHostController = TextEditingController();
  final _proxyPortController = TextEditingController();
  final _proxyUsernameController = TextEditingController();
  final _proxyPasswordController = TextEditingController();
  RemoteStorageConfig? _authorizedBaiduConfig;
  String _proxyMode = kAccountProxyModeInherit;
  String _proxyType = 'http';
  String _baiduAuthUrl = '';
  String? _baiduAuthErrorText;
  bool _openingBaiduAuthPage = false;
  bool _authorizingBaidu = false;
  bool _mappedBucketNameEdited = false;
  bool _usePathStyle = true;
  List<BucketInfo> _availableBuckets = const [];
  Map<String, BucketViewSettings> _bucketViews = <String, BucketViewSettings>{};
  bool _loadingBuckets = false;

  // Wizard state — step 0 = protocol picker, step 1 = connection fields.
  int _step = 0;
  bool _saving = false;
  String? _errorText;
  String _initialAccessKey = '';
  bool _validatingCredentials = false;
  bool _credentialsValidated = false;
  String? _credentialValidationText;

  /// Exposed for part-file step functions to trigger rebuilds.
  void markDirty(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    if (config == null) return;
    _storageType = config.storageType;
    _nameController.text = config.displayName;
    _mappedBucketNameController.text = config.mappedBucketName;
    _endpointController.text = config.endpoint;
    _regionController.text = config.region.isEmpty ? 'auto' : config.region;
    _accessKeyController.text = config.accessKeyId;
    _initialAccessKey = config.accessKeyId.trim();
    _webdavUsernameController.text = config.webdavUsername;
    _ftpUsernameController.text = config.ftpUsername;
    if (config.ftpPort > 0) {
      _ftpPortController.text = config.ftpPort.toString();
    }
    _ftpAnonymous = config.ftpAnonymous;
    _usePathStyle = config.usePathStyle;
    _bucketViews = Map<String, BucketViewSettings>.from(config.bucketViews);
    _proxyMode = config.proxyMode;
    _proxyType = config.proxyType;
    _proxyHostController.text = config.proxyHost;
    _proxyPortController.text = config.proxyPort;
    _proxyUsernameController.text = config.proxyUsername;
    _proxyPasswordController.text = config.proxyPassword;
    if (config.storageType == StorageType.baiduPan) {
      _authorizedBaiduConfig = config;
    }
    // Editing skips the protocol picker (step 0) since the protocol is fixed.
    if (widget.editing) _step = 1;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mappedBucketNameController.dispose();
    _endpointController.dispose();
    _regionController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _webdavUsernameController.dispose();
    _webdavPasswordController.dispose();
    _ftpUsernameController.dispose();
    _ftpPasswordController.dispose();
    _ftpPortController.dispose();
    _baiduAuthCodeController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _proxyUsernameController.dispose();
    _proxyPasswordController.dispose();
    super.dispose();
  }

  // -- Sub-window content-fit -------------------------------------------------

  /// Content width for the sub-window form body (shell adds horizontal padding).
  static const double _contentWidth = 600;

  Size? _latestContentSize;
  int _fitGeneration = 0;
  bool _fitInFlight = false;

  void _onContentSize(Size contentSize) {
    if (widget.asDialog) return;
    if (contentSize.width <= 0 || contentSize.height <= 0) return;
    _latestContentSize = contentSize;
    _fitGeneration++;
    _drainContentFit();
  }

  Future<void> _drainContentFit() async {
    if (_fitInFlight || widget.asDialog) return;
    _fitInFlight = true;
    try {
      while (mounted && !widget.asDialog) {
        final gen = _fitGeneration;
        final size = _latestContentSize;
        if (size == null) break;
        try {
          await fitModalSubWindowToContentSize(
            size,
            creatorWindowId: widget.creatorWindowId,
            creatorFrameLeft: widget.creatorFrameLeft,
            creatorFrameTop: widget.creatorFrameTop,
            creatorFrameWidth: widget.creatorFrameWidth,
            creatorFrameHeight: widget.creatorFrameHeight,
          );
        } catch (_) {}
        if (gen == _fitGeneration) break;
      }
    } finally {
      _fitInFlight = false;
    }
  }

  Widget _wrapMeasured(Widget child) {
    if (widget.asDialog) return child;
    // Measure unconstrained content height at fixed form width; shell padding
    // and title bar are added inside fitModalSubWindowToContentSize.
    return MeasureSize(
      onChange: _onContentSize,
      contentWidth: _contentWidth,
      child: child,
    );
  }

  // -- Step navigation --------------------------------------------------------

  Future<void> _next() async {
    if (_step < 1) {
      setState(() {
        _errorText = null;
        _step++;
      });
      return;
    }
    if (_step == 1) {
      if (widget.editing || widget.simpleMode) {
        await _submit();
      } else {
        await _loadBucketsForVisibility();
      }
      return;
    }
    await _submit();
  }

  void _back() {
    if (_step <= 0) return;
    setState(() {
      _errorText = null;
      _step--;
    });
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    // Editing: single-screen form, no wizard chrome.
    if (widget.editing) {
      final content = _buildEditContent(theme);
      if (!widget.asDialog) return _wrapMeasured(content);
      return AppShadDialog(
        title: const Text('编辑账号'),
        description: const Text('修改账号连接信息；密钥、密码或 OAuth 授权会按你当前选择保留或更新。'),
        constraints: const BoxConstraints(maxWidth: 640),
        scrollable: true,
        child: content,
      );
    }
    // New account: wizard. Sub-window measures shrink-wrapped content
    // and resizes the OS window to fit (no empty bottom / no inner scroll).
    if (!widget.asDialog) {
      return _wrapMeasured(_buildWizardContent(theme));
    }
    return AppShadDialog(
      title: Text(widget.simpleMode ? '配置独立备份存储' : '新增账号'),
      description: Text(
        widget.simpleMode
            ? '选择存储类型并填写连接信息，配好后可直接选择保存位置。'
            : '先选择存储类型，再填写对应的连接信息。',
      ),
      constraints: const BoxConstraints(maxWidth: 640),
      scrollable: true,
      child: _buildWizardContent(theme),
    );
  }

  /// Builds the shared wizard content (step body + nav buttons). Both
  /// new-account and editing modes use this layout now that editing also
  /// advances through the bucket-visibility step.
  Widget _buildWizardContent(ShadThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  /// Editing mode: just the connection fields + nav buttons.
  Widget _buildEditContent(ShadThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        stepConnectionFields(theme: theme, self: this),
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
        _buildEditNavButtons(theme),
      ],
    );
  }

  Widget _buildStepBody(ShadThemeData theme) {
    return switch (_step) {
      0 => stepProtocolPicker(theme: theme, self: this),
      1 =>
        _loadingBuckets
            ? const Center(child: AppLoadingIndicator())
            : stepConnectionFields(theme: theme, self: this),
      _ => stepBucketVisibility(theme: theme, self: this),
    };
  }

  /// Builds the navigation row for the new-account wizard. In editing mode
  /// the protocol step is skipped, so the "上一步" button is hidden on the
  /// connection step and shown once we move to the bucket-visibility step.
  Widget _buildNavButtons(ShadThemeData theme) {
    final isLast = _step == 2;
    // simpleMode skips the bucket-visibility step, so step 1 is the last.
    final isSimpleLast = widget.simpleMode && _step == 1;
    final isFirst = widget.editing || widget.simpleMode
        ? _step <= 1
        : _step <= 0;
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 10,
        children: [
          ShadButton.outline(
            onPressed: widget.asDialog
                ? () => Navigator.of(context).pop()
                : widget.onCancel,
            child: const Text('取消'),
          ),
          if (!isFirst) ...[
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
            onPressed: _saving || _loadingBuckets ? null : _next,
            child: _saving
                ? const Text('保存中...')
                : Row(
                    children: [
                      Text(
                        isSimpleLast
                            ? '保存'
                            : isLast
                            ? '保存账号'
                            : '下一步',
                      ),
                      if (!isLast && !isSimpleLast) ...[
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.chevronRight, size: 16),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Editing mode nav buttons: just Cancel + Save.
  Widget _buildEditNavButtons(ShadThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 10,
        children: [
          ShadButton.outline(
            onPressed: widget.asDialog
                ? () => Navigator.of(context).pop()
                : widget.onCancel,
            child: const Text('取消'),
          ),
          ShadButton(
            onPressed: _saving ? null : _submit,
            child: _saving ? const Text('保存中...') : const Text('保存修改'),
          ),
        ],
      ),
    );
  }

  // -- Submit & helpers -------------------------------------------------------
  // Protocol-specific field builders (_s3Fields / _webdavFields / _baiduPanFields)
  // live in the part file cloud_storage_account_dialog_steps.dart.

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final config = _draftConfig();
    final saved = await widget.onSave(config);
    if (!mounted) return;
    if (saved) {
      widget.onSaved?.call();
      if (widget.asDialog) Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _errorText = '保存失败，请检查配置';
      });
    }
  }
}
