// 桶设置弹窗：编辑桶级配额、只读与回收站策略。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const int _bytesPerGigabyte = 1024 * 1024 * 1024;
const double _maxCustomQuotaGb = 8 * 1024 * 1024;

Widget _dialogActionWrap(List<Widget> actions) => SizedBox(
  width: double.infinity,
  child: Wrap(
    alignment: WrapAlignment.end,
    spacing: 10,
    runSpacing: 10,
    children: actions,
  ),
);

Future<RemoteStorageConfig?> showBucketSettingsDialog(
  BuildContext context, {
  required String bucket,
  required RemoteStorageConfig config,
}) {
  final current = config.bucketSettingsFor(bucket);
  final trashController = TextEditingController(text: current.trashDirectory);
  final quotaController = TextEditingController(
    text: _quotaGigabytesText(current.customQuotaBytes),
  );
  final volumeLabelController = TextEditingController(
    text: current.winFspVolumeLabel,
  );
  var readOnly = current.readOnly;
  var trashEnabled = current.isTrashEnabled;
  String? quotaError;

  return showAppModal<RemoteStorageConfig?>(
    context: context,
    builder: (dialogContext) {
      return AppShadDialog(
        title: const Text('桶设置'),
        description: Text('配置「$bucket」的配额、只读和回收站策略。'),
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
                    onChanged: (value) =>
                        setDialogState(() => readOnly = value),
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
                  Text(
                    '自定义配额 (GB)',
                    style: theme.textTheme.small.copyWith(
                      color: theme.colorScheme.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: quotaController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    placeholder: const Text('0'),
                    onChanged: (_) {
                      if (quotaError != null) {
                        setDialogState(() => quotaError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    quotaError ?? '0 或留空时显示服务端配额（如支持）。',
                    style: TextStyle(
                      fontSize: 12,
                      color: quotaError == null
                          ? theme.colorScheme.mutedForeground
                          : theme.colorScheme.destructive,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'WinFsp 盘符名称',
                    style: theme.textTheme.small.copyWith(
                      color: theme.colorScheme.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: volumeLabelController,
                    maxLength: 32,
                    placeholder: const Text('默认：Cloud Volume <桶名>'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '仅用于 Windows WinFsp 挂载；留空时使用默认名称。修改后重新挂载生效。',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.mutedForeground,
                    ),
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
                  _dialogActionWrap([
                    ShadButton.outline(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('取消'),
                    ),
                    ShadButton(
                      onPressed: () {
                        final customQuotaBytes = _parseQuotaBytes(
                          quotaController.text,
                        );
                        if (customQuotaBytes == null) {
                          setDialogState(
                            () => quotaError =
                                '请输入 0 到 ${_maxCustomQuotaGb.toInt()} 之间的数值。',
                          );
                          return;
                        }
                        final trimmed = trashController.text.trim();
                        final nextSettings = Map<String, BucketSettings>.from(
                          config.bucketSettings,
                        );
                        nextSettings[bucket] = BucketSettings(
                          readOnly: readOnly,
                          trashEnabled: trashEnabled,
                          trashDirectory: trimmed,
                          customQuotaBytes: customQuotaBytes,
                          winFspVolumeLabel: volumeLabelController.text.trim(),
                        );
                        Navigator.of(
                          dialogContext,
                        ).pop(config.copyWith(bucketSettings: nextSettings));
                      },
                      child: const Text('保存'),
                    ),
                  ]),
                ],
              ),
            );
          },
        ),
      );
    },
  ).whenComplete(() {
    trashController.dispose();
    quotaController.dispose();
    volumeLabelController.dispose();
  });
}

String _quotaGigabytesText(int bytes) {
  if (bytes <= 0) return '0';
  final value = bytes / _bytesPerGigabyte;
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

int? _parseQuotaBytes(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 0;
  final gigabytes = double.tryParse(trimmed);
  if (gigabytes == null ||
      !gigabytes.isFinite ||
      gigabytes < 0 ||
      gigabytes > _maxCustomQuotaGb) {
    return null;
  }
  return (gigabytes * _bytesPerGigabyte).round();
}
