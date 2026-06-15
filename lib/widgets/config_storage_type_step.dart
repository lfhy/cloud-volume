// 初始化账号类型选择面板，负责把首次配置拆成清晰的第一步。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// First-run storage account type chooser.
class ConfigStorageTypeStep extends StatelessWidget {
  const ConfigStorageTypeStep({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
    required this.onNext,
  });

  final StorageType selectedType;
  final ValueChanged<StorageType> onTypeChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
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
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '添加存储账号',
                        style: theme.textTheme.h3.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.foreground,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '先选择账号类型，下一步再填写连接信息。',
                        style: TextStyle(
                          color: theme.colorScheme.mutedForeground,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _typeTile(
                        context,
                        type: StorageType.s3,
                        icon: Icons.storage_outlined,
                        title: 'S3 对象存储',
                        description: '适用于 MinIO、私有 S3 和其他 S3 兼容对象存储。',
                      ),
                      const SizedBox(height: 12),
                      _typeTile(
                        context,
                        type: StorageType.webdav,
                        icon: Icons.cloud_queue_outlined,
                        title: 'WebDAV',
                        description: '适用于支持 WebDAV 协议的网盘或文件服务。',
                      ),
                      const SizedBox(height: 12),
                      _typeTile(
                        context,
                        type: StorageType.baiduPan,
                        icon: Icons.cloud_sync_outlined,
                        title: '百度网盘',
                        description: '通过百度网盘 OpenAPI + OAuth 登录个人网盘账号。',
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 44,
                        child: ShadButton(
                          onPressed: onNext,
                          child: const Text(
                            '下一步',
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

  Widget _typeTile(
    BuildContext context, {
    required StorageType type,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = ShadTheme.of(context);
    final selected = selectedType == type;
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.border;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onTypeChanged(type),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.06)
                : theme.colorScheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: theme.colorScheme.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
