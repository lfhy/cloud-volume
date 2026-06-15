// 百度网盘授权区统一展示 OOB 授权说明、授权码输入与提交入口。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remote_storage/widgets/cloud_storage_account_form_field.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class BaiduPanAuthSection extends StatelessWidget {
  const BaiduPanAuthSection({
    super.key,
    required this.accountLabel,
    required this.authorized,
    required this.codeController,
    required this.openingBrowser,
    required this.submittingCode,
    required this.onOpenAuthorizationPage,
    required this.onSubmitAuthorizationCode,
    this.authUrl = '',
    this.errorText,
  });

  final String accountLabel;
  final bool authorized;
  final TextEditingController codeController;
  final bool openingBrowser;
  final bool submittingCode;
  final VoidCallback onOpenAuthorizationPage;
  final VoidCallback onSubmitAuthorizationCode;
  final String authUrl;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accent = authorized
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;
    final statusText = authorized
        ? '已授权：${accountLabel.trim().isEmpty ? '百度网盘账号' : accountLabel.trim()}'
        : '尚未授权';
    final helperText = authorized
        ? '上传会先进入 /apps/网盘demo/，再自动移动到你当前选择的目标目录。'
        : '点击“打开授权页”后会使用百度要求的 oob 模式打开浏览器，请把网页显示的授权码粘贴回这里完成登录。';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                authorized ? Icons.verified_outlined : Icons.key_outlined,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            helperText,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          if (authUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _AuthUrlBlock(authUrl: authUrl),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: openingBrowser ? null : onOpenAuthorizationPage,
                  child: Text(openingBrowser ? '正在打开...' : '打开授权页'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ShadButton(
                  onPressed: submittingCode ? null : onSubmitAuthorizationCode,
                  child: Text(submittingCode ? '提交中...' : '提交授权码'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CloudStorageTechnicalInput(
            controller: codeController,
            placeholder: const Text('粘贴百度授权页显示的授权码'),
          ),
          if (errorText != null && errorText!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              errorText!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthUrlBlock extends StatelessWidget {
  const _AuthUrlBlock({required this.authUrl});

  final String authUrl;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              authUrl,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => Clipboard.setData(ClipboardData(text: authUrl)),
            child: const Text('复制链接'),
          ),
        ],
      ),
    );
  }
}
