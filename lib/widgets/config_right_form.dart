// 右侧表单面板：有空间时垂直居中，空间不足时回退为可滚动布局。
// 这样大窗口不会显得偏上，小窗口也不会把提交按钮挤出可视区域。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/widgets/baidu_pan_auth_section.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';

/// 配置页右侧完整表单。
class ConfigRightFormPanel extends StatelessWidget {
  const ConfigRightFormPanel({
    super.key,
    required this.storageType,
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
    required this.isSaving,
    required this.errorText,
    required this.onSave,
    this.onBack,
  });

  final StorageType storageType;
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
  final bool isSaving;
  final String? errorText;
  final VoidCallback onSave;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isWebDav = storageType == StorageType.webdav;
    final isBaiduPan = storageType == StorageType.baiduPan;
    final title = isBaiduPan
        ? '添加百度网盘账号'
        : isWebDav
        ? '添加 WebDAV 账号'
        : '添加 S3 对象存储账号';
    final subtitle = isBaiduPan
        ? '通过百度要求的 oob 授权码流程完成百度网盘 OpenAPI 登录。'
        : isWebDav
        ? '填写 WebDAV 服务地址和登录账号。'
        : '填写对象存储端点和访问密钥。';

    return Container(
      color: theme.colorScheme.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = constraints.maxHeight;
          final minContentHeight = viewportHeight > 64
              ? viewportHeight - 64
              : viewportHeight;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minContentHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
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
                        const SizedBox(height: 18),
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
                      const SizedBox(height: 28),
                      _sectionLabel(context, '连接信息'),
                      const SizedBox(height: 16),
                      _fieldLabel(context, '名称'),
                      const SizedBox(height: 6),
                      ShadInput(
                        controller: nameController,
                        placeholder: Text(
                          isBaiduPan
                              ? '例如：我的百度网盘'
                              : isWebDav
                              ? '例如：IHEP WebDAV'
                              : '例如：对象存储账号',
                        ),
                        onChanged: onNameChanged,
                      ),
                      if (isWebDav) ...[
                        const SizedBox(height: 18),
                        _fieldLabel(context, '映射桶名称'),
                        const SizedBox(height: 6),
                        ShadInput(
                          controller: mappedBucketNameController,
                          placeholder: const Text('默认使用名称'),
                          onChanged: onMappedBucketNameChanged,
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (!isWebDav && !isBaiduPan) ...[
                        const SizedBox(height: 18),
                      ],
                      if (isBaiduPan) ...[
                        const SizedBox(height: 18),
                        BaiduPanAuthSection(
                          accountLabel: baiduPanAccountLabel,
                          authorized: baiduPanAuthorized,
                          codeController: baiduPanCodeController,
                          authUrl: baiduPanAuthUrl,
                          openingBrowser: baiduPanOpeningBrowser,
                          submittingCode: baiduPanAuthorizing,
                          onOpenAuthorizationPage: onStartBaiduPanAuthorization,
                          onSubmitAuthorizationCode: onAuthorizeBaiduPan,
                        ),
                      ] else ...[
                        _fieldLabel(context, isWebDav ? 'WebDAV 地址' : '网关地址'),
                        const SizedBox(height: 6),
                        CloudStorageTechnicalInput(
                          controller: endpointController,
                          keyboardType: TextInputType.url,
                          placeholder: Text(
                            isWebDav
                                ? 'https://dav.example.com/remote.php/dav/files/me'
                                : 'https://s3.example.com',
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],
                      if (!isBaiduPan &&
                          isWebDav &&
                          webdavUsernameController != null &&
                          webdavPasswordController != null) ...[
                        _fieldLabel(context, '用户名'),
                        const SizedBox(height: 6),
                        CloudStorageTechnicalInput(
                          controller: webdavUsernameController!,
                          placeholder: const Text('输入 WebDAV 用户名'),
                        ),
                        const SizedBox(height: 18),
                        _fieldLabel(context, '密码'),
                        const SizedBox(height: 6),
                        CloudStorageSecretInput(
                          controller: webdavPasswordController!,
                          placeholder: Text(
                            hasStoredWebdavPassword
                                ? '留空则保留当前已保存的 WebDAV 密码'
                                : '输入 WebDAV 登录密码',
                          ),
                        ),
                      ] else if (!isBaiduPan) ...[
                        // 访问密钥 ID。
                        _fieldLabel(context, '访问密钥 ID'),
                        const SizedBox(height: 6),
                        CloudStorageTechnicalInput(
                          controller: accessKeyController,
                          placeholder: const Text('输入 Access Key ID'),
                        ),
                        const SizedBox(height: 18),
                        // 访问密钥。
                        _fieldLabel(context, '访问密钥'),
                        const SizedBox(height: 6),
                        CloudStorageSecretInput(
                          controller: secretKeyController,
                          placeholder: Text(
                            hasStoredSecretKey
                                ? '留空则保留当前已保存的 Secret Access Key'
                                : '输入 Secret Access Key',
                          ),
                        ),
                      ],
                      // 高级设置入口。
                      if (!isWebDav && !isBaiduPan) ...[
                        const SizedBox(height: 18),
                        _AdvancedSettingsLink(
                          onTap: isSaving
                              ? null
                              : () => _openAdvancedDialog(context),
                        ),
                      ],
                      // 错误提示。
                      if (errorText != null) ...[
                        const SizedBox(height: 16),
                        _errorBanner(context, errorText!),
                      ],
                      const SizedBox(height: 24),
                      // 底部保存按钮。
                      SizedBox(
                        width: double.infinity,
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
                                        color:
                                            theme.colorScheme.primaryForeground,
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
  void _openAdvancedDialog(BuildContext context) {
    final rgCtrl = TextEditingController(text: regionController.text);
    var pathStyle = usePathStyle;

    showShadDialog(
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
