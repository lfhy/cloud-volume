// 首次启动配置页：左右等分布局，内容延伸至标题栏下方。
// 左侧：品牌面板。右侧：表单。组件拆分至 widgets/ 目录。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/config_left_panel.dart';
import 'package:remote_storage/widgets/config_right_form.dart';
import 'package:remote_storage/widgets/config_storage_type_step.dart';

// 首次运行预设默认值。
const _kDefaultEndpoint = 'https://fgws3-ocloud.ihep.ac.cn';
const _kDefaultRegion = 'auto';
const _kBaiduPanEndpoint = 'https://pan.baidu.com';

enum _SetupStep { chooseType, accountForm }

class ConfigSetupPage extends StatefulWidget {
  const ConfigSetupPage({
    super.key,
    required this.api,
    required this.initialState,
    required this.onSaved,
  });

  final RemoteStorageGateway api;
  final BootstrapState initialState;
  final VoidCallback onSaved;

  @override
  State<ConfigSetupPage> createState() => _ConfigSetupPageState();
}

class _ConfigSetupPageState extends State<ConfigSetupPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _endpointController;
  late final TextEditingController _mappedBucketNameController;
  late final TextEditingController _regionController;
  late final TextEditingController _accessKeyController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _webdavUsernameController;
  late final TextEditingController _webdavPasswordController;
  late final TextEditingController _baiduAuthCodeController;
  RemoteStorageConfig? _authorizedBaiduConfig;
  String _baiduAuthUrl = '';

  _SetupStep _step = _SetupStep.chooseType;
  late StorageType _storageType;
  late bool _usePathStyle;
  bool _openingBaiduAuthPage = false;
  bool _authorizingBaidu = false;
  bool _mappedBucketNameEdited = false;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final config = widget.initialState.config;
    _storageType = config.storageType;
    _nameController = TextEditingController(
      text: config.displayName.trim().isNotEmpty
          ? config.displayName
          : config.storageType == StorageType.webdav
          ? 'WebDAV'
          : config.storageType == StorageType.baiduPan
          ? '百度网盘'
          : 'S3',
    );
    // 首次运行时使用默认值。
    _mappedBucketNameController = TextEditingController(
      text: config.mappedBucketName.trim().isNotEmpty
          ? config.mappedBucketName
          : config.storageType == StorageType.webdav
          ? 'WebDAV'
          : config.storageType == StorageType.baiduPan
          ? '百度网盘'
          : 'S3',
    );
    _endpointController = TextEditingController(
      text: config.endpoint.trim().isNotEmpty
          ? config.endpoint
          : config.storageType == StorageType.baiduPan
          ? _kBaiduPanEndpoint
          : config.storageType == StorageType.s3
          ? _kDefaultEndpoint
          : '',
    );
    _regionController = TextEditingController(
      text: config.region.trim().isNotEmpty ? config.region : _kDefaultRegion,
    );
    _accessKeyController = TextEditingController(text: config.accessKeyId);
    _secretKeyController = TextEditingController();
    _webdavUsernameController = TextEditingController(
      text: config.webdavUsername,
    );
    _webdavPasswordController = TextEditingController();
    _baiduAuthCodeController = TextEditingController();
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

  void _selectStorageType(StorageType type) {
    setState(() {
      _storageType = type;
      if (type == StorageType.s3 && _endpointController.text.trim().isEmpty) {
        _endpointController.text = _kDefaultEndpoint;
      }
      if (type == StorageType.baiduPan) {
        _endpointController.text = _kBaiduPanEndpoint;
      }
      if (type == StorageType.webdav &&
          _endpointController.text.trim() == _kDefaultEndpoint) {
        _endpointController.clear();
      }
      final mappedName = _mappedBucketNameController.text.trim();
      if (mappedName.isEmpty ||
          mappedName == 'S3' ||
          mappedName == 'WebDAV' ||
          mappedName == '百度网盘') {
        _mappedBucketNameController.text = type == StorageType.webdav
            ? 'WebDAV'
            : type == StorageType.baiduPan
            ? '百度网盘'
            : 'S3';
      }
      if (_nameController.text.trim().isEmpty ||
          _nameController.text.trim() == 'S3' ||
          _nameController.text.trim() == 'WebDAV' ||
          _nameController.text.trim() == '百度网盘') {
        _nameController.text = type == StorageType.webdav
            ? 'WebDAV'
            : type == StorageType.baiduPan
            ? '百度网盘'
            : 'S3';
      }
    });
  }

  Future<void> _save() async {
    final isWebDav = _storageType == StorageType.webdav;
    final isBaiduPan = _storageType == StorageType.baiduPan;
    final name = _nameController.text.trim();
    final config = RemoteStorageConfig(
      endpoint: isBaiduPan
          ? (_authorizedBaiduConfig?.endpoint ?? _kBaiduPanEndpoint)
          : _endpointController.text,
      storageType: _storageType,
      providerType: isBaiduPan
          ? StorageProviderType.baiduPan
          : widget.initialState.config.providerType,
      displayName: name,
      mappedBucketName: isWebDav
          ? (_mappedBucketNameController.text.trim().isNotEmpty
                ? _mappedBucketNameController.text
                : name)
          : isBaiduPan
          ? (name.isEmpty ? '百度网盘' : name)
          : name,
      region: _regionController.text,
      bucket: widget.initialState.config.bucket,
      accessKeyId: isBaiduPan
          ? (_authorizedBaiduConfig?.accessKeyId ?? '')
          : isWebDav
          ? ''
          : _accessKeyController.text,
      secretAccessKey: isBaiduPan
          ? (_authorizedBaiduConfig?.secretAccessKey ?? '')
          : isWebDav
          ? ''
          : _secretKeyController.text,
      hasSecretAccessKey: isBaiduPan
          ? (_authorizedBaiduConfig?.hasSecretAccessKey ?? false)
          : !isWebDav && widget.initialState.config.hasSecretAccessKey,
      webdavUsername: isWebDav
          ? _webdavUsernameController.text
          : isBaiduPan
          ? ''
          : _accessKeyController.text,
      webdavPassword: isWebDav
          ? _webdavPasswordController.text
          : isBaiduPan
          ? ''
          : _secretKeyController.text,
      hasWebdavPassword:
          isWebDav && widget.initialState.config.hasWebdavPassword,
      rootPrefix: widget.initialState.config.rootPrefix,
      defaultDownloadDirectory:
          widget.initialState.config.defaultDownloadDirectory,
      cacheDirectory: widget.initialState.config.cacheDirectory,
      resolvedCacheDirectory: widget.initialState.config.resolvedCacheDirectory,
      hideDotFiles: widget.initialState.config.hideDotFiles,
      // 文件浏览固定为单击打开，配置阶段不再暴露这个开关。
      fileOpenMode: FileOpenMode.singleClick,
      trashDirectoryName: widget.initialState.config.trashDirectoryName,
      trashRetentionDays: widget.initialState.config.trashRetentionDays,
      bucketSettings: widget.initialState.config.bucketSettings,
      writebackQuietSeconds: widget.initialState.config.writebackQuietSeconds,
      mountMetadataCacheSeconds:
          widget.initialState.config.mountMetadataCacheSeconds,
      usePathStyle: _usePathStyle,
      windowsMountMode: widget.initialState.config.windowsMountMode,
      windowsThisPcEntryEnabled:
          widget.initialState.config.windowsThisPcEntryEnabled,
      windowsWritebackConcurrency:
          widget.initialState.config.windowsWritebackConcurrency,
    );

    if (!config.isConfigured) {
      setState(() {
        _errorText = isBaiduPan
            ? '请先完成百度网盘 OAuth 授权。'
            : isWebDav
            ? '请填写 WebDAV 地址、用户名和密码。'
            : '请填写 Endpoint、Access Key 和 Secret Key。';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await widget.api.saveConfig(config);
      if (!mounted) return;
      widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = describeBridgeError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 左右等分，视觉更平衡。
          Expanded(
            child: ConfigLeftPanel(configPath: widget.initialState.configPath),
          ),
          Expanded(
            child: _step == _SetupStep.chooseType
                ? ConfigStorageTypeStep(
                    selectedType: _storageType,
                    onTypeChanged: _selectStorageType,
                    onNext: () => setState(() {
                      _errorText = null;
                      _step = _SetupStep.accountForm;
                    }),
                  )
                : ConfigRightFormPanel(
                    storageType: _storageType,
                    nameController: _nameController,
                    mappedBucketNameController: _mappedBucketNameController,
                    onNameChanged: _syncMappedBucketNameFromName,
                    onMappedBucketNameChanged: (_) {
                      _mappedBucketNameEdited = true;
                    },
                    endpointController: _endpointController,
                    regionController: _regionController,
                    accessKeyController: _accessKeyController,
                    secretKeyController: _secretKeyController,
                    hasStoredSecretKey:
                        widget.initialState.config.hasSecretAccessKey,
                    webdavUsernameController: _webdavUsernameController,
                    webdavPasswordController: _webdavPasswordController,
                    hasStoredWebdavPassword:
                        widget.initialState.config.hasWebdavPassword,
                    baiduPanAuthorized:
                        _authorizedBaiduConfig?.hasSecretAccessKey == true &&
                        _authorizedBaiduConfig?.accessKeyId.trim().isNotEmpty ==
                            true,
                    baiduPanAccountLabel:
                        _authorizedBaiduConfig?.displayName.trim().isNotEmpty ==
                            true
                        ? _authorizedBaiduConfig!.displayName
                        : _nameController.text.trim(),
                    baiduPanCodeController: _baiduAuthCodeController,
                    baiduPanAuthUrl: _baiduAuthUrl,
                    baiduPanOpeningBrowser: _openingBaiduAuthPage,
                    baiduPanAuthorizing: _authorizingBaidu,
                    onStartBaiduPanAuthorization: _startBaiduPanAuthorization,
                    onAuthorizeBaiduPan: _authorizeBaiduPan,
                    usePathStyle: _usePathStyle,
                    onPathStyleChanged: (v) =>
                        setState(() => _usePathStyle = v),
                    isSaving: _isSaving,
                    errorText: _errorText,
                    onSave: _save,
                    onBack: () => setState(() {
                      _errorText = null;
                      _step = _SetupStep.chooseType;
                    }),
                  ),
          ),
        ],
      ),
    );
  }

  void _syncMappedBucketNameFromName(String value) {
    if (_storageType != StorageType.webdav || _mappedBucketNameEdited) {
      return;
    }
    _mappedBucketNameController.text = value;
  }

  Future<void> _authorizeBaiduPan() async {
    final code = _baiduAuthCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorText = '请先粘贴百度授权页显示的授权码。';
      });
      return;
    }
    setState(() => _authorizingBaidu = true);
    try {
      final config = await widget.api.authorizeBaiduPan(
        _nameController.text.trim(),
        code,
      );
      if (!mounted) return;
      setState(() {
        _authorizedBaiduConfig = config;
        _baiduAuthCodeController.clear();
        _errorText = null;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = config.displayName;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = describeBridgeError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _authorizingBaidu = false);
      }
    }
  }

  Future<void> _startBaiduPanAuthorization() async {
    setState(() => _openingBaiduAuthPage = true);
    try {
      final authUrl = await widget.api.startBaiduPanAuthorization();
      if (!mounted) return;
      setState(() {
        _baiduAuthUrl = authUrl;
        _errorText = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = describeBridgeError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _openingBaiduAuthPage = false);
      }
    }
  }
}
