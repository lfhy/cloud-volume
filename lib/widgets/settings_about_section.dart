// 关于页分区组件：集中展示版本、作者版权和社区联系方式。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingsAboutSection extends StatelessWidget {
  const SettingsAboutSection({
    super.key,
    required this.theme,
    required this.versionText,
  });

  final ShadThemeData theme;
  final String versionText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '云卷当前版本、作者署名与社区联系方式。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 14),
        _AboutInfoBlock(
          theme: theme,
          label: '产品名称',
          value: '云卷 / Cloud Volume',
        ),
        const SizedBox(height: 10),
        _AboutInfoBlock(theme: theme, label: '版本信息', value: versionText),
        const SizedBox(height: 10),
        _AboutInfoBlock(
          theme: theme,
          label: '作者 / 版权',
          value: 'Copyright © 三千',
        ),
        const SizedBox(height: 10),
        _AboutInfoBlock(theme: theme, label: '交流群', value: 'QQ 交流群 572532027'),
      ],
    );
  }
}

class _AboutInfoBlock extends StatelessWidget {
  const _AboutInfoBlock({
    required this.theme,
    required this.label,
    required this.value,
  });

  final ShadThemeData theme;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
