// 账号重置分区组件：危险操作，清空所有已保存账号并回到首次启动流程。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/services/app_modal.dart';

Widget _dialogActionWrap(List<Widget> actions) => SizedBox(
  width: double.infinity,
  child: Wrap(
    alignment: WrapAlignment.end,
    spacing: 10,
    runSpacing: 10,
    children: actions,
  ),
);

/// [SettingsResetUserConfigSection] 暴露“重置账号”入口，点击后会弹出二次确认，
/// 确认后调用上层传入的 [onReset]，由设置页执行 bridge 重置并刷新启动状态。
class SettingsResetUserConfigSection extends StatelessWidget {
  const SettingsResetUserConfigSection({
    super.key,
    required this.theme,
    required this.busy,
    required this.errorText,
    required this.onReset,
  });

  final ShadThemeData theme;
  final bool busy;
  final String? errorText;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '清空所有已保存的账号、密钥与 WebDAV 凭据，应用会回到首次启动的初始化流程。'
          '已挂载的桶与缓存目录不受影响，可重新配置后继续使用。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 12),
        if (errorText != null) ...[
          Text(
            errorText!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
          const SizedBox(height: 10),
        ],
        ShadButton.destructive(
          onPressed: busy ? null : () => _confirmAndReset(context),
          child: Text(busy ? '重置中...' : '重置全部账号'),
        ),
      ],
    );
  }

  Future<void> _confirmAndReset(BuildContext context) async {
    final confirmed = await showAppModal<bool>(
      context: context,
      builder: (dialogContext) => AppShadDialog(
        title: const Text('确认重置账号'),
        description: const Text('该操作会清空所有已保存账号，且无法撤销。'),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                '确认要清除全部账号信息并回到首次启动配置页吗？',
                style: TextStyle(
                  fontSize: 12,
                  color: ShadTheme.of(
                    dialogContext,
                  ).colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: 18),
              _dialogActionWrap([
                ShadButton.outline(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                ShadButton.destructive(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('确认重置'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    await onReset();
  }
}
