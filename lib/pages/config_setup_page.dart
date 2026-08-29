// 首次启动配置页：协议选择 → 全屏账号表单；步骤切换只做轻量宽度/淡入动画。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/theme/list_interaction_colors.dart';
import 'package:remote_storage/widgets/config_backup_restore.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/cloud_storage_account_dialog.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/widgets/settings_config_backup_labels.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/config_left_panel.dart';
import 'package:remote_storage/widgets/config_right_form.dart';
import 'package:remote_storage/widgets/config_storage_type_step.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'config_setup_baidu_auth.dart';
part 'config_setup_restore.dart';

// 首次运行预设默认网关（IHEP 对象存储 / WebDAV）。
const _kDefaultS3Endpoint = 'https://fgws3-ocloud.ihep.ac.cn';
const _kDefaultWebDavEndpoint = 'https://webdav-ocloud.ihep.ac.cn';
const _kDefaultRegion = 'auto';
const _kBaiduPanEndpoint = 'https://pan.baidu.com';

// 分栏 ↔ 全屏切换动画时长，保持短促避免拖沓。
const _kStepAnimDuration = Duration(milliseconds: 240);

/// 是否仍是首次引导里的预设地址（用户未手改时允许随协议切换）。
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
  late final TextEditingController _ftpUsernameController;
  late final TextEditingController _ftpPasswordController;
  late final TextEditingController _ftpPortController;
  late final TextEditingController _baiduAuthCodeController;
  RemoteStorageConfig? _authorizedBaiduConfig;
  String _baiduAuthUrl = '';

  _SetupStep _step = _SetupStep.chooseType;
  late StorageType _storageType;
  late bool _usePathStyle;
  late JWanFSGatewayMode _jwanfsGatewayMode;
  bool _openingBaiduAuthPage = false;
  bool _authorizingBaidu = false;
  bool _mappedBucketNameEdited = false;
  bool _isSaving = false;
  String? _errorText;

  void _updateState(VoidCallback action) => setState(action);

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
          : config.storageType == StorageType.sftp
          ? 'SFTP'
          : config.storageType == StorageType.ftp
          ? 'FTP'
          : 'S3',
    );
    _mappedBucketNameController = TextEditingController(
      text: config.mappedBucketName.trim().isNotEmpty
          ? config.mappedBucketName
          : config.storageType == StorageType.webdav
          ? 'WebDAV'
          : config.storageType == StorageType.baiduPan
          ? '百度网盘'
          : config.storageType == StorageType.sftp
          ? 'SFTP'
          : config.storageType == StorageType.ftp
          ? 'FTP'
          : 'S3',
    );
    _endpointController = TextEditingController(
      text: config.endpoint.trim().isNotEmpty
          ? config.endpoint
          : _defaultEndpointFor(config.storageType),
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
    _ftpUsernameController = TextEditingController(text: config.ftpUsername);
    _ftpPasswordController = TextEditingController();
    _ftpPortController = TextEditingController(
      text: config.ftpPort > 0 ? config.ftpPort.toString() : '',
    );
    _baiduAuthCodeController = TextEditingController();
    _usePathStyle = config.usePathStyle;
    _jwanfsGatewayMode = config.jwanfsGatewayMode;
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
    _ftpUsernameController.dispose();
    _ftpPasswordController.dispose();
    _ftpPortController.dispose();
    _baiduAuthCodeController.dispose();
    super.dispose();
  }

  void _selectStorageType(StorageType type) {
    setState(() {
      _storageType = type;
      if (type == StorageType.baiduPan ||
          _isPresetEndpoint(_endpointController.text)) {
        _endpointController.text = _defaultEndpointFor(type);
      }
      final mappedName = _mappedBucketNameController.text.trim();
      if (mappedName.isEmpty ||
          mappedName == 'S3' ||
          mappedName == 'WebDAV' ||
          mappedName == '百度网盘' ||
          mappedName == 'FTP' ||
          mappedName == 'SFTP') {
        _mappedBucketNameController.text = type == StorageType.webdav
            ? 'WebDAV'
            : type == StorageType.baiduPan
            ? '百度网盘'
            : type == StorageType.sftp
            ? 'SFTP'
            : type == StorageType.ftp
            ? 'FTP'
            : 'S3';
      }
      if (_nameController.text.trim().isEmpty ||
          _nameController.text.trim() == 'S3' ||
          _nameController.text.trim() == 'WebDAV' ||
          _nameController.text.trim() == '百度网盘' ||
          _nameController.text.trim() == 'FTP' ||
          _nameController.text.trim() == 'SFTP') {
        _nameController.text = type == StorageType.webdav
            ? 'WebDAV'
            : type == StorageType.baiduPan
            ? '百度网盘'
            : type == StorageType.sftp
            ? 'SFTP'
            : type == StorageType.ftp
            ? 'FTP'
            : 'S3';
      }
    });
  }

  Future<void> _save() async {
    final isWebDav = _storageType == StorageType.webdav;
    final isBaiduPan = _storageType == StorageType.baiduPan;
    final isFTP =
        _storageType == StorageType.ftp || _storageType == StorageType.sftp;
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
      mappedBucketName: isWebDav || isFTP
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
          : isWebDav || isFTP
          ? ''
          : _accessKeyController.text,
      secretAccessKey: isBaiduPan
          ? (_authorizedBaiduConfig?.secretAccessKey ?? '')
          : isWebDav || isFTP
          ? ''
          : _secretKeyController.text,
      hasSecretAccessKey: isBaiduPan
          ? (_authorizedBaiduConfig?.hasSecretAccessKey ?? false)
          : !isWebDav &&
                !isFTP &&
                widget.initialState.config.hasSecretAccessKey,
      webdavUsername: isWebDav
          ? _webdavUsernameController.text
          : isBaiduPan || isFTP
          ? ''
          : _accessKeyController.text,
      webdavPassword: isWebDav
          ? _webdavPasswordController.text
          : isBaiduPan || isFTP
          ? ''
          : _secretKeyController.text,
      hasWebdavPassword:
          isWebDav && widget.initialState.config.hasWebdavPassword,
      ftpUsername: isFTP ? _ftpUsernameController.text : '',
      ftpPassword: isFTP ? _ftpPasswordController.text : '',
      hasFtpPassword: isFTP && widget.initialState.config.hasFtpPassword,
      ftpPort: isFTP ? (int.tryParse(_ftpPortController.text.trim()) ?? 0) : 0,
      ftpAnonymous: false,
      rootPrefix: widget.initialState.config.rootPrefix,
      defaultDownloadDirectory:
          widget.initialState.config.defaultDownloadDirectory,
      cacheDirectory: widget.initialState.config.cacheDirectory,
      resolvedCacheDirectory: widget.initialState.config.resolvedCacheDirectory,
      hideDotFiles: widget.initialState.config.hideDotFiles,
      fileOpenMode: FileOpenMode.singleClick,
      trashDirectoryName: widget.initialState.config.trashDirectoryName,
      trashRetentionDays: widget.initialState.config.trashRetentionDays,
      bucketSettings: widget.initialState.config.bucketSettings,
      bucketViews: widget.initialState.config.bucketViews,
      writebackQuietSeconds: widget.initialState.config.writebackQuietSeconds,
      mountMetadataCacheSeconds:
          widget.initialState.config.mountMetadataCacheSeconds,
      mountRemotePollSeconds: widget.initialState.config.mountRemotePollSeconds,
      usePathStyle: _usePathStyle,
      windowsMountMode: widget.initialState.config.windowsMountMode,
      windowsMountEngine: widget.initialState.config.windowsMountEngine,
      windowsWinFspCapacityGb:
          widget.initialState.config.windowsWinFspCapacityGb,
      windowsThisPcEntryEnabled:
          widget.initialState.config.windowsThisPcEntryEnabled,
      windowsWritebackConcurrency:
          widget.initialState.config.windowsWritebackConcurrency,
      cacheAutoCleanupEnabled:
          widget.initialState.config.cacheAutoCleanupEnabled,
      cacheMaxSizeMb: widget.initialState.config.cacheMaxSizeMb,
      cacheMaxAgeDays: widget.initialState.config.cacheMaxAgeDays,
      jwanfsGatewayMode: _jwanfsGatewayMode,
      proxyMode: widget.initialState.config.proxyMode,
      proxyType: widget.initialState.config.proxyType,
      proxyHost: widget.initialState.config.proxyHost,
      proxyPort: widget.initialState.config.proxyPort,
      proxyUsername: widget.initialState.config.proxyUsername,
      proxyPassword: widget.initialState.config.proxyPassword,
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

  void _goToAccountForm() {
    if (_isSaving || _step == _SetupStep.accountForm) return;
    if (_isPresetEndpoint(_endpointController.text)) {
      _endpointController.text = _defaultEndpointFor(_storageType);
    }
    setState(() {
      _errorText = null;
      _step = _SetupStep.accountForm;
    });
  }

  void _goBackToChooseType() {
    if (_isSaving || _step == _SetupStep.chooseType) return;
    setState(() {
      _errorText = null;
      _step = _SetupStep.chooseType;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAccountForm = _step == _SetupStep.accountForm;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
      body: isAndroid
          ? _buildAndroidBody(isAccountForm)
          : LayoutBuilder(
              builder: (context, constraints) {
                final brandWidth = constraints.maxWidth * 0.5;
                return Row(
                  children: [
                    TweenAnimationBuilder<double>(
                      duration: _kStepAnimDuration,
                      curve: Curves.easeOutCubic,
                      tween: Tween<double>(end: isAccountForm ? 0 : 1),
                      builder: (context, factor, child) {
                        return ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: factor.clamp(0.0, 1.0),
                            child: child,
                          ),
                        );
                      },
                      child: SizedBox(
                        width: brandWidth,
                        child: ConfigLeftPanel(
                          configPath: widget.initialState.configPath,
                        ),
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: _kStepAnimDuration,
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        layoutBuilder: (currentChild, _) {
                          return currentChild ?? const SizedBox.shrink();
                        },
                        child: isAccountForm
                            ? ConfigRightFormPanel(
                                key: const ValueKey('setup-account-form'),
                                storageType: _storageType,
                                fullWidth: true,
                                nameController: _nameController,
                                mappedBucketNameController:
                                    _mappedBucketNameController,
                                onNameChanged: _syncMappedBucketNameFromName,
                                onMappedBucketNameChanged: (_) {
                                  _mappedBucketNameEdited = true;
                                },
                                endpointController: _endpointController,
                                regionController: _regionController,
                                accessKeyController: _accessKeyController,
                                secretKeyController: _secretKeyController,
                                hasStoredSecretKey: widget
                                    .initialState
                                    .config
                                    .hasSecretAccessKey,
                                webdavUsernameController:
                                    _webdavUsernameController,
                                webdavPasswordController:
                                    _webdavPasswordController,
                                ftpUsernameController: _ftpUsernameController,
                                ftpPasswordController: _ftpPasswordController,
                                ftpPortController: _ftpPortController,
                                ftpAnonymous: false,
                                hasStoredFtpPassword:
                                    widget.initialState.config.hasFtpPassword,
                                hasStoredWebdavPassword: widget
                                    .initialState
                                    .config
                                    .hasWebdavPassword,
                                onFieldsChanged: () => setState(() {}),
                                baiduPanAuthorized:
                                    _authorizedBaiduConfig
                                            ?.hasSecretAccessKey ==
                                        true &&
                                    _authorizedBaiduConfig?.accessKeyId
                                            .trim()
                                            .isNotEmpty ==
                                        true,
                                baiduPanAccountLabel:
                                    _authorizedBaiduConfig?.displayName
                                            .trim()
                                            .isNotEmpty ==
                                        true
                                    ? _authorizedBaiduConfig!.displayName
                                    : _nameController.text.trim(),
                                baiduPanCodeController:
                                    _baiduAuthCodeController,
                                baiduPanAuthUrl: _baiduAuthUrl,
                                baiduPanOpeningBrowser: _openingBaiduAuthPage,
                                baiduPanAuthorizing: _authorizingBaidu,
                                onStartBaiduPanAuthorization:
                                    _startBaiduPanAuthorization,
                                onAuthorizeBaiduPan: _authorizeBaiduPan,
                                usePathStyle: _usePathStyle,
                                onPathStyleChanged: (v) =>
                                    setState(() => _usePathStyle = v),
                                jwanfsGatewayMode: _jwanfsGatewayMode,
                                onJWanFSGatewayModeChanged: (v) =>
                                    setState(() => _jwanfsGatewayMode = v),
                                isSaving: _isSaving,
                                errorText: _errorText,
                                onSave: _save,
                                onBack: _goBackToChooseType,
                              )
                            : ConfigStorageTypeStep(
                                key: const ValueKey('setup-choose-type'),
                                selectedType: _storageType,
                                onTypeChanged: _selectStorageType,
                                onNext: _goToAccountForm,
                                onRestoreFromBackup: _openRestoreFromBackup,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildAndroidBody(bool isAccountForm) {
    return SafeArea(
      child: AnimatedSwitcher(
        duration: _kStepAnimDuration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: isAccountForm
            ? ConfigRightFormPanel(
                key: const ValueKey('setup-account-form-mobile'),
                storageType: _storageType,
                fullWidth: true,
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
                ftpUsernameController: _ftpUsernameController,
                ftpPasswordController: _ftpPasswordController,
                ftpPortController: _ftpPortController,
                ftpAnonymous: false,
                hasStoredFtpPassword: widget.initialState.config.hasFtpPassword,
                hasStoredWebdavPassword:
                    widget.initialState.config.hasWebdavPassword,
                onFieldsChanged: () => setState(() {}),
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
                onPathStyleChanged: (v) => setState(() => _usePathStyle = v),
                jwanfsGatewayMode: _jwanfsGatewayMode,
                onJWanFSGatewayModeChanged: (v) =>
                    setState(() => _jwanfsGatewayMode = v),
                isSaving: _isSaving,
                errorText: _errorText,
                onSave: _save,
                onBack: _goBackToChooseType,
              )
            : ConfigStorageTypeStep(
                key: const ValueKey('setup-choose-type-mobile'),
                selectedType: _storageType,
                onTypeChanged: _selectStorageType,
                onNext: _goToAccountForm,
                onRestoreFromBackup: _openRestoreFromBackup,
              ),
      ),
    );
  }

  void _syncMappedBucketNameFromName(String value) {
    if (_storageType != StorageType.webdav || _mappedBucketNameEdited) {
      return;
    }
    _mappedBucketNameController.text = value;
  }
}

/// Hover-aware snapshot tile for the first-run restore dialog.
class _RestoreSnapshotTile extends StatefulWidget {
  const _RestoreSnapshotTile({
    required this.label,
    required this.latest,
    required this.onRestore,
    this.encrypted = false,
  });

  final String label;
  final bool latest;
  final Future<void> Function() onRestore;

  /// When true, shows a lock badge to indicate an encrypted snapshot that
  /// will prompt for a password on restore.
  final bool encrypted;

  @override
  State<_RestoreSnapshotTile> createState() => _RestoreSnapshotTileState();
}
