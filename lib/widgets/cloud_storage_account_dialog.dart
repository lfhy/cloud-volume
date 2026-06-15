// 新增账号弹窗先选择存储类型，再展示对应的认证字段。
// 表单沿用配置初始化引导页的“标签 + 输入框”样式，便于用户辨识每一项。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';
import 'package:remote_storage/widgets/baidu_pan_auth_section.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 新增/编辑账号时提交给上层的草稿数据。
class CloudStorageAccountDraft {
  const CloudStorageAccountDraft({
    required this.storageType,
    required this.name,
    required this.mappedBucketName,
    required this.endpoint,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.usePathStyle,
    required this.webdavUsername,
    required this.webdavPassword,
    required this.baiduAccessToken,
    required this.baiduRefreshToken,
    required this.hasBaiduRefreshToken,
  });

  final StorageType storageType;
  final String name;
  final String mappedBucketName;
  final String endpoint;
  final String region;
  final String accessKey;
  final String secretKey;
  final bool usePathStyle;
  final String webdavUsername;
  final String webdavPassword;
  final String baiduAccessToken;
  final String baiduRefreshToken;
  final bool hasBaiduRefreshToken;
}

/// 账号管理页使用的新增/编辑账号对话框。
class CloudStorageAccountDialog extends StatefulWidget {
  const CloudStorageAccountDialog({
    super.key,
    required this.onSave,
    required this.onStartBaiduPanAuthorization,
    required this.onAuthorizeBaiduPan,
    this.initialConfig,
    this.editing = false,
  });

  final Future<bool> Function(CloudStorageAccountDraft draft) onSave;
  final Future<String> Function() onStartBaiduPanAuthorization;
  final Future<RemoteStorageConfig> Function(String displayName, String code)
  onAuthorizeBaiduPan;
  final RemoteStorageConfig? initialConfig;
  final bool editing;

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
  final _baiduAuthCodeController = TextEditingController();
  RemoteStorageConfig? _authorizedBaiduConfig;
  String _baiduAuthUrl = '';
  String? _baiduAuthErrorText;
  bool _openingBaiduAuthPage = false;
  bool _authorizingBaidu = false;
  bool _mappedBucketNameEdited = false;
  bool _usePathStyle = true;

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
    _webdavUsernameController.text = config.webdavUsername;
    _usePathStyle = config.usePathStyle;
    if (config.storageType == StorageType.baiduPan) {
      _authorizedBaiduConfig = config;
    }
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
    _baiduAuthCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWebDav = _storageType == StorageType.webdav;
    final isBaiduPan = _storageType == StorageType.baiduPan;
    return ShadDialog(
      title: Text(widget.editing ? '编辑账号' : '新增账号'),
      description: Text(
        widget.editing
            ? '修改账号连接信息；密钥、密码或 OAuth 授权会按你当前选择保留或更新。'
            : '先选择存储类型，再填写对应的连接信息。',
      ),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StorageTypeSegmentedControl(
              value: _storageType,
              onChanged: (value) => setState(() => _storageType = value),
            ),
            const SizedBox(height: 18),
            CloudStorageLabeledField(
              label: '名称',
              child: ShadInput(
                controller: _nameController,
                placeholder: Text(
                  isBaiduPan
                      ? '例如：我的百度网盘'
                      : isWebDav
                      ? '例如：IHEP WebDAV'
                      : '例如：对象存储账号',
                ),
                onChanged: (_) => _syncMappedBucketName(),
              ),
            ),
            if (isWebDav) ...[
              const SizedBox(height: 14),
              CloudStorageLabeledField(
                label: '映射桶名称',
                child: ShadInput(
                  controller: _mappedBucketNameController,
                  placeholder: const Text('默认使用名称'),
                  onChanged: (_) => _mappedBucketNameEdited = true,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (isBaiduPan) ..._baiduPanFields(),
            if (!isBaiduPan && !isWebDav) ..._s3Fields(),
            if (!isBaiduPan && isWebDav) ..._webdavFields(),
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
                  onPressed: _submit,
                  child: Text(widget.editing ? '保存修改' : '保存账号'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _s3Fields() {
    return [
      CloudStorageLabeledField(
        label: '网关地址',
        child: CloudStorageTechnicalInput(
          controller: _endpointController,
          keyboardType: TextInputType.url,
          placeholder: const Text('https://s3.example.com'),
        ),
      ),
      const SizedBox(height: 14),
      CloudStorageLabeledField(
        label: '区域',
        child: CloudStorageTechnicalInput(
          controller: _regionController,
          placeholder: const Text('Region，例如 auto'),
        ),
      ),
      const SizedBox(height: 14),
      CloudStorageLabeledField(
        label: '访问密钥 ID',
        child: CloudStorageTechnicalInput(
          controller: _accessKeyController,
          placeholder: const Text('Access Key ID'),
        ),
      ),
      const SizedBox(height: 14),
      CloudStorageLabeledField(
        label: '访问密钥',
        child: CloudStorageSecretInput(
          controller: _secretKeyController,
          placeholder: Text(
            widget.editing ? '留空则保留当前 Secret Key' : 'Secret Access Key',
          ),
        ),
      ),
      const SizedBox(height: 16),
      _S3AdvancedOptions(
        usePathStyle: _usePathStyle,
        onPathStyleChanged: (value) => setState(() => _usePathStyle = value),
      ),
    ];
  }

  List<Widget> _webdavFields() {
    return [
      CloudStorageLabeledField(
        label: 'WebDAV 地址',
        child: CloudStorageTechnicalInput(
          controller: _endpointController,
          keyboardType: TextInputType.url,
          placeholder: const Text(
            'https://dav.example.com/remote.php/dav/files/me',
          ),
        ),
      ),
      const SizedBox(height: 14),
      CloudStorageLabeledField(
        label: '用户名',
        child: CloudStorageTechnicalInput(
          controller: _webdavUsernameController,
          placeholder: const Text('输入 WebDAV 用户名'),
        ),
      ),
      const SizedBox(height: 14),
      CloudStorageLabeledField(
        label: '密码',
        child: CloudStorageSecretInput(
          controller: _webdavPasswordController,
          placeholder: Text(
            widget.editing ? '留空则保留当前 WebDAV 密码' : '输入 WebDAV 登录密码',
          ),
        ),
      ),
    ];
  }

  List<Widget> _baiduPanFields() {
    final label = _authorizedBaiduConfig?.displayName.trim().isNotEmpty == true
        ? _authorizedBaiduConfig!.displayName
        : _nameController.text.trim();
    return [
      BaiduPanAuthSection(
        accountLabel: label,
        authorized:
            _authorizedBaiduConfig?.accessKeyId.trim().isNotEmpty == true &&
            _authorizedBaiduConfig?.hasSecretAccessKey == true,
        codeController: _baiduAuthCodeController,
        authUrl: _baiduAuthUrl,
        openingBrowser: _openingBaiduAuthPage,
        submittingCode: _authorizingBaidu,
        onOpenAuthorizationPage: _startBaiduPanAuthorization,
        onSubmitAuthorizationCode: _authorizeBaiduPan,
        errorText: _baiduAuthErrorText,
      ),
    ];
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final baiduConfig = _authorizedBaiduConfig;
    final mappedBucketName = _storageType == StorageType.webdav
        ? (_mappedBucketNameController.text.trim().isEmpty
              ? name
              : _mappedBucketNameController.text)
        : _storageType == StorageType.baiduPan
        ? (name.isEmpty ? '百度网盘' : name)
        : _nameController.text;
    final saved = await widget.onSave(
      CloudStorageAccountDraft(
        storageType: _storageType,
        name: name,
        mappedBucketName: mappedBucketName,
        endpoint: _storageType == StorageType.baiduPan
            ? (baiduConfig?.endpoint ?? 'https://pan.baidu.com')
            : _endpointController.text,
        region: _regionController.text,
        accessKey: _storageType == StorageType.baiduPan
            ? (baiduConfig?.accessKeyId ?? '')
            : _accessKeyController.text,
        secretKey: _storageType == StorageType.baiduPan
            ? (baiduConfig?.secretAccessKey ?? '')
            : _secretKeyController.text,
        usePathStyle: _usePathStyle,
        webdavUsername: _webdavUsernameController.text,
        webdavPassword: _webdavPasswordController.text,
        baiduAccessToken: baiduConfig?.accessKeyId ?? '',
        baiduRefreshToken: baiduConfig?.secretAccessKey ?? '',
        hasBaiduRefreshToken: baiduConfig?.hasSecretAccessKey ?? false,
      ),
    );
    if (saved && mounted) Navigator.of(context).pop();
  }

  void _syncMappedBucketName() {
    if (widget.editing || _mappedBucketNameEdited) {
      return;
    }
    _mappedBucketNameController.text = _nameController.text;
  }

  Future<void> _authorizeBaiduPan() async {
    final code = _baiduAuthCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _baiduAuthErrorText = '请先粘贴百度授权页显示的授权码。';
      });
      return;
    }
    setState(() {
      _authorizingBaidu = true;
      _baiduAuthErrorText = null;
    });
    try {
      final config = await widget.onAuthorizeBaiduPan(
        _nameController.text.trim(),
        code,
      );
      if (!mounted) return;
      setState(() {
        _authorizedBaiduConfig = config;
        _baiduAuthCodeController.clear();
        _baiduAuthErrorText = null;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = config.displayName;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _baiduAuthErrorText = describeBridgeError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _authorizingBaidu = false);
      }
    }
  }

  Future<void> _startBaiduPanAuthorization() async {
    setState(() {
      _openingBaiduAuthPage = true;
      _baiduAuthErrorText = null;
    });
    try {
      final authUrl = await widget.onStartBaiduPanAuthorization();
      if (!mounted) return;
      setState(() {
        _baiduAuthUrl = authUrl;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _baiduAuthErrorText = describeBridgeError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _openingBaiduAuthPage = false);
      }
    }
  }
}

class _S3AdvancedOptions extends StatelessWidget {
  const _S3AdvancedOptions({
    required this.usePathStyle,
    required this.onPathStyleChanged,
  });

  final bool usePathStyle;
  final ValueChanged<bool> onPathStyleChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ShadSwitch(
        value: usePathStyle,
        onChanged: onPathStyleChanged,
        label: Text(
          '使用路径风格访问',
          style: theme.textTheme.small.copyWith(
            color: theme.colorScheme.foreground,
            fontWeight: FontWeight.w500,
          ),
        ),
        sublabel: Text(
          '推荐用于 MinIO、私有 S3 和多数兼容对象存储。',
          style: TextStyle(
            color: theme.colorScheme.mutedForeground,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _StorageTypeSegmentedControl extends StatelessWidget {
  const _StorageTypeSegmentedControl({
    required this.value,
    required this.onChanged,
  });

  final StorageType value;
  final ValueChanged<StorageType> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        for (final item in StorageType.values) ...[
          Expanded(
            child: ShadButton(
              size: ShadButtonSize.sm,
              onPressed: () => onChanged(item),
              backgroundColor: item == value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.secondary,
              foregroundColor: item == value
                  ? theme.colorScheme.primaryForeground
                  : theme.colorScheme.foreground,
              child: Text(item.label),
            ),
          ),
          if (item != StorageType.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
