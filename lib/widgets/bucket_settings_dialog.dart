// 桶设置弹窗：负责编辑桶级只读、回收站开关和回收站目录覆盖。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Future<RemoteStorageConfig?> showBucketSettingsDialog(
  BuildContext context, {
  required String bucket,
  required RemoteStorageConfig config,
}) {
  final current = config.bucketSettingsFor(bucket);
  final trashController = TextEditingController(text: current.trashDirectory);
  var readOnly = current.readOnly;
  var trashEnabled = current.isTrashEnabled;

  return showShadDialog<RemoteStorageConfig?>(
    context: context,
    builder: (dialogContext) {
      return ShadDialog(
        title: const Text('桶设置'),
        description: Text('配置「$bucket」的只读和回收站策略。'),
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final theme = ShadTheme.of(dialogContext);
            return SizedBox(
              width: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  ShadSwitch(
                    value: readOnly,
                    onChanged: (value) => setDialogState(() => readOnly = value),
                    label: Text(
                      '只读桶',
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    sublabel: const Text('开启后将拒绝上传、新建、删除、改名、移动等写操作。'),
                  ),
                  const SizedBox(height: 14),
                  ShadSwitch(
                    value: trashEnabled,
                    onChanged: (value) =>
                        setDialogState(() => trashEnabled = value),
                    label: Text(
                      '启用回收站',
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    sublabel: Text(
                      config.storageType == StorageType.webdav
                          ? 'WebDAV 可改到可写子目录，例如 20134-image/.trash。'
                          : '关闭后删除将直接硬删除，不再进入回收站。',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '回收站目录',
                    style: theme.textTheme.small.copyWith(
                      color: theme.colorScheme.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: trashController,
                    enabled: trashEnabled,
                    placeholder: Text(
                      config.storageType == StorageType.webdav
                          ? '例如：20134-image/.trash'
                          : '默认：.trash',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '留空时继承系统设置中的默认回收站目录：${config.trashDirectoryName}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 18),
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
                          final trimmed = trashController.text.trim();
                          final nextSettings = Map<String, BucketSettings>.from(
                            config.bucketSettings,
                          );
                          nextSettings[bucket] = BucketSettings(
                            readOnly: readOnly,
                            trashEnabled: trashEnabled,
                            trashDirectory: trimmed,
                          );
                          Navigator.of(dialogContext).pop(
                            config.copyWith(bucketSettings: nextSettings),
                          );
                        },
                        child: const Text('保存'),
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
  ).whenComplete(trashController.dispose);
}

