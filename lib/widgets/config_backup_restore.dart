// 配置备份还原的密码输入弹窗 + 解密失败重试循环。
// 首次启动引导页和设置页历史弹窗共用这一份实现，避免两条还原路径的行为
// （是否重试、何时弹密码框、空密码如何处理）悄悄分叉。

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 用户取消密码输入或页面在还原途中销毁时抛出，调用方静默收尾即可，
/// 不要把它当作「还原失败」toast 出来。
class ConfigBackupRestoreCancelled implements Exception {
  const ConfigBackupRestoreCancelled();

  @override
  String toString() => 'ConfigBackupRestoreCancelled';
}

/// 用 [target] + [password] 尝试还原 [key]；解密失败就循环弹密码框让用户
/// 重新输入，直到还原成功、用户取消（抛 [ConfigBackupRestoreCancelled]）、
/// 或遇到非解密类错误（原样向上抛）。
///
/// [password] 起点一般用 `target.backupPassword`；若调用方已经拿它尝试过
/// 且确认是解密错误，传 [skipInitialAttempt] 直接弹密码框，避免再跑一次
/// 必然失败的下载 + 解密。密码提交为空时会在弹窗内提示，不会被误当取消。
Future<BootstrapState> restoreConfigBackupWithPasswordRetry({
  required BuildContext context,
  required bool Function() isMounted,
  required RemoteStorageGateway api,
  required ConfigBackupTarget target,
  required String key,
  required String label,
  bool skipInitialAttempt = false,
}) async {
  var password = target.backupPassword;
  var needsPrompt = skipInitialAttempt;
  while (true) {
    if (needsPrompt) {
      if (!isMounted() || !context.mounted) {
        throw const ConfigBackupRestoreCancelled();
      }
      final entered = await showConfigBackupPasswordPrompt(
        context: context,
        snapshotLabel: label,
      );
      if (entered == null) {
        throw const ConfigBackupRestoreCancelled();
      }
      password = entered;
      target = target.copyWith(backupPassword: entered);
    }
    needsPrompt = true;
    try {
      return await api.restoreConfigBackupWithTarget(
        target,
        key,
        password: password,
      );
    } catch (error) {
      if (!isConfigBackupDecryptionError(error)) {
        rethrow;
      }
      // 下一轮循环弹密码框重试。
    }
  }
}

/// 弹出备份密码输入框。返回用户输入的非空密码；取消或页面销毁返回 null。
/// 提交空密码时在弹窗内提示，不会关闭弹窗，避免「取消」与「没输入」混淆。
Future<String?> showConfigBackupPasswordPrompt({
  required BuildContext context,
  required String snapshotLabel,
}) async {
  final controller = TextEditingController();
  final emptyError = ValueNotifier<bool>(false);
  var obscure = true;
  String? entered;
  await showAppModalDialog<void>(
    context: context,
    title: const Text('输入备份密码'),
    description: Text('备份 $snapshotLabel 已加密，请输入加密时设置的备份密码。'),
    maxWidth: 420,
    child: StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShadInput(
              controller: controller,
              obscureText: obscure,
              autofocus: true,
              placeholder: const Text('输入备份密码'),
              onChanged: (_) {
                if (emptyError.value) {
                  emptyError.value = false;
                }
              },
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty) {
                  emptyError.value = true;
                  return;
                }
                entered = trimmed;
                Navigator.of(dialogContext).pop();
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ShadSwitch(
                  value: !obscure,
                  onChanged: (v) => setDialogState(() => obscure = !v),
                ),
                const SizedBox(width: 8),
                Text(
                  '显示密码',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        ShadTheme.of(dialogContext).colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
            ValueListenableBuilder<bool>(
              valueListenable: emptyError,
              builder: (context, showError, _) {
                if (!showError) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '请输入备份密码，或点取消退出还原。',
                    style: TextStyle(
                      fontSize: 12,
                      color: ShadTheme.of(dialogContext)
                          .colorScheme
                          .destructive,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    ),
    actions: [
      Builder(
        builder: (dialogContext) => ShadButton.outline(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
      ),
      Builder(
        builder: (dialogContext) => ShadButton(
          onPressed: () {
            final trimmed = controller.text.trim();
            if (trimmed.isEmpty) {
              emptyError.value = true;
              return;
            }
            entered = trimmed;
            Navigator.of(dialogContext).pop();
          },
          child: const Text('确定'),
        ),
      ),
    ],
  );
  emptyError.dispose();
  controller.dispose();
  return entered;
}
