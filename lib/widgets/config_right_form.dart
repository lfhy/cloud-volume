// 配置页账号表单：半宽时垂直居中；全屏时隐藏左侧宣传后使用更宽布局。
// 宽屏全屏模式会把字段拆成两列，减少单页滚动。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/widgets/baidu_pan_auth_section.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';
import 'package:remote_storage/services/app_modal.dart';

part 'config_right_form_fields.dart';

/// 配置页账号表单。
class ConfigRightFormPanel extends StatelessWidget {
  const ConfigRightFormPanel({
    super.key,
    required this.storageType,
    this.fullWidth = false,
    required this.nameController,
    required this.mappedBucketNameController,
    this.onNameChanged,
    this.onMappedBucketNameChanged,
    required this.endpointController,
    required this.regionController,
    required this.accessKeyController,
    required this.secretKeyController,
    required this.hasStoredSecretKey,
    required this.webdavUsernameController,
    required this.webdavPasswordController,
    required this.ftpUsernameController,
    required this.ftpPasswordController,
    required this.ftpPortController,
    required this.ftpAnonymous,
    this.hasStoredFtpPassword = false,
    required this.hasStoredWebdavPassword,
    required this.baiduPanAuthorized,
    required this.baiduPanAccountLabel,
    required this.baiduPanCodeController,
    required this.baiduPanAuthUrl,
    required this.baiduPanOpeningBrowser,
    required this.baiduPanAuthorizing,
    required this.onStartBaiduPanAuthorization,
    required this.onAuthorizeBaiduPan,
    required this.usePathStyle,
    required this.onPathStyleChanged,
    required this.jwanfsGatewayMode,
    required this.onJWanFSGatewayModeChanged,
    required this.isSaving,
    required this.errorText,
    required this.onSave,
    this.onBack,
    this.onFieldsChanged,
  });

  final StorageType storageType;

  /// 首次启动第二步：占满整页，隐藏左侧宣传后使用更宽表单。
  final bool fullWidth;
  final TextEditingController nameController;
  final TextEditingController mappedBucketNameController;
  final ValueChanged<String>? onNameChanged;
  final ValueChanged<String>? onMappedBucketNameChanged;
  final TextEditingController endpointController;
  final TextEditingController regionController;
  final TextEditingController accessKeyController;
  final TextEditingController secretKeyController;
  final bool hasStoredSecretKey;
  final TextEditingController? webdavUsernameController;
  final TextEditingController? webdavPasswordController;
  final TextEditingController? ftpUsernameController;
  final TextEditingController? ftpPasswordController;
  final TextEditingController? ftpPortController;
  final bool ftpAnonymous;
  final bool hasStoredFtpPassword;
  final bool hasStoredWebdavPassword;
  final bool baiduPanAuthorized;
  final String baiduPanAccountLabel;
  final TextEditingController baiduPanCodeController;
  final String baiduPanAuthUrl;
  final bool baiduPanOpeningBrowser;
  final bool baiduPanAuthorizing;
  final VoidCallback onStartBaiduPanAuthorization;
  final VoidCallback onAuthorizeBaiduPan;
  final bool usePathStyle;
  final ValueChanged<bool> onPathStyleChanged;
  final JWanFSGatewayMode jwanfsGatewayMode;
  final ValueChanged<JWanFSGatewayMode> onJWanFSGatewayModeChanged;
  final bool isSaving;
  final String? errorText;
  final VoidCallback onSave;
  final VoidCallback? onBack;

  /// 刷新协议切换前的字段可见性（如 FTP 匿名开关会隐藏账号密码）。
  final VoidCallback? onFieldsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isWebDav = storageType == StorageType.webdav;
    final isBaiduPan = storageType == StorageType.baiduPan;
    final isFTP =
        storageType == StorageType.ftp || storageType == StorageType.sftp;
    final ftpLabel = storageType == StorageType.sftp ? 'SFTP' : 'FTP';
    final title = isBaiduPan
        ? '添加百度网盘账号'
        : isWebDav
        ? '添加 WebDAV 账号'
        : isFTP
        ? '添加 $ftpLabel 账号'
        : '添加 S3 对象存储账号';
    final subtitle = isBaiduPan
        ? '通过百度要求的 oob 授权码流程完成百度网盘 OpenAPI 登录。'
        : isWebDav
        ? '填写 WebDAV 服务地址和登录账号。'
        : isFTP
        ? '填写 $ftpLabel 服务器地址、端口和登录账号。'
        : '填写对象存储端点和访问密钥。';

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    return Container(
      color: theme.colorScheme.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = constraints.maxHeight;
          final minContentHeight = viewportHeight > 64
              ? viewportHeight - 64
              : viewportHeight;
          // 全屏表单更宽；半宽模式保持原先窄卡片观感。
          final maxFormWidth = isAndroid
              ? 420.0
              : fullWidth
              ? 720.0
              : 380.0;
          final useTwoColumns =
              fullWidth &&
              !isAndroid &&
              !isBaiduPan &&
              constraints.maxWidth >= 700;
          final horizontalPadding = isAndroid
              ? 20.0
              : fullWidth
              ? 48.0
              : 32.0;
          final verticalPadding = isAndroid
              ? 18.0
              : fullWidth
              ? 28.0
              : 32.0;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minContentHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxFormWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (onBack != null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ShadButton.ghost(
                            size: ShadButtonSize.sm,
                            onPressed: isSaving ? null : onBack,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_back, size: 15),
                                SizedBox(width: 6),
                                Text('返回'),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: fullWidth ? 12 : 18),
                      ],
                      // 标题。
                      Text(
                        title,
                        style: theme.textTheme.h3.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.foreground,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: theme.colorScheme.mutedForeground,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      SizedBox(height: fullWidth ? 22 : 28),
                      _sectionLabel(context, '连接信息'),
                      const SizedBox(height: 16),
                      if (useTwoColumns)
                        buildConfigFormTwoColumnFields(this, context)
                      else
                        buildConfigFormSingleColumnFields(
                          this,
                          context,
                          isBaiduPan: isBaiduPan,
                        ),
                      // 错误提示。
                      if (errorText != null) ...[
                        const SizedBox(height: 16),
                        _errorBanner(context, errorText!),
                      ],
                      const SizedBox(height: 24),
                      // 底部保存按钮。
                      Align(
                        alignment: fullWidth && !isAndroid
                            ? Alignment.centerRight
                            : Alignment.center,
                        child: SizedBox(
                          width: isAndroid
                              ? double.infinity
                              : fullWidth
                              ? 220
                              : double.infinity,
                          height: 44,
                          child: ShadButton(
                            onPressed: isSaving ? null : onSave,
                            child: isSaving
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: AppLoadingIndicator(
                                          strokeWidth: 2,
                                          color: theme
                                              .colorScheme
                                              .primaryForeground,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('保存中...'),
                                    ],
                                  )
                                : const Text(
                                    '确认添加',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final theme = ShadTheme.of(context);
    return Text(
      text,
      style: TextStyle(
        color: theme.colorScheme.mutedForeground,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String text) {
    final theme = ShadTheme.of(context);
    return Text(
      text,
      style: TextStyle(
        color: theme.colorScheme.foreground,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _errorBanner(BuildContext context, String text) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.destructive.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.destructive.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 15,
            color: theme.colorScheme.destructive,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.destructive,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 打开高级设置弹窗。
  void openAdvancedDialog(BuildContext context) {
    final rgCtrl = TextEditingController(text: regionController.text);
    var pathStyle = usePathStyle;
    var gatewayMode = jwanfsGatewayMode;

    showAppModal(
      context: context,
      builder: (dialogContext) {
        return ShadDialog(
          title: const Text('高级设置'),
          description: const Text('配置区域和连接选项。'),
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final theme = ShadTheme.of(dialogContext);
              return SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    _fieldLabel(dialogContext, '区域'),
                    const SizedBox(height: 5),
                    CloudStorageTechnicalInput(
                      controller: rgCtrl,
                      placeholder: const Text('auto / us-east-1'),
                    ),
                    const SizedBox(height: 16),
                    ShadSwitch(
                      value: pathStyle,
                      onChanged: (v) => setDialogState(() => pathStyle = v),
                      label: Text(
                        '使用路径风格访问',
                        style: theme.textTheme.small.copyWith(
                          color: theme.colorScheme.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      sublabel: Text(
                        '推荐用于大多数 S3 兼容及私有对象存储。',
                        style: TextStyle(
                          color: theme.colorScheme.mutedForeground,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _fieldLabel(dialogContext, '存储网关类型'),
                    const SizedBox(height: 5),
                    ShadSelect<JWanFSGatewayMode>(
                      initialValue: gatewayMode,
                      placeholder: Text(gatewayMode.label),
                      selectedOptionBuilder: (context, selected) =>
                          Text(selected.label),
                      options: JWanFSGatewayMode.values
                          .map(
                            (mode) => ShadOption<JWanFSGatewayMode>(
                              value: mode,
                              child: Text(mode.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => gatewayMode = v);
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      gatewayMode.description,
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ShadButton.outline(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 10),
                        ShadButton(
                          onPressed: () {
                            regionController.text = rgCtrl.text;
                            onPathStyleChanged(pathStyle);
                            onJWanFSGatewayModeChanged(gatewayMode);
                            Navigator.of(dialogContext).pop();
                          },
                          child: const Text('确认'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 高级设置文字链接。
class _AdvancedSettingsLink extends StatelessWidget {
  const _AdvancedSettingsLink({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = theme.colorScheme.primary;
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_outlined, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              '高级设置',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
