// 网关切换弹窗：展示所有配置文件，支持切换。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/services/app_modal.dart';

class ProfilePickerDialog extends StatelessWidget {
  const ProfilePickerDialog({
    super.key,
    required this.profiles,
    required this.activeProfile,
    required this.onSwitch,
  });

  final List<ProfileInfo> profiles;
  final String activeProfile;
  final ValueChanged<String> onSwitch;

  static Future<void> show(
    BuildContext context, {
    required List<ProfileInfo> profiles,
    required String activeProfile,
    required ValueChanged<String> onSwitch,
  }) {
    return showAppModal(
      context: context,
      builder: (_) => ProfilePickerDialog(
        profiles: profiles,
        activeProfile: activeProfile,
        onSwitch: onSwitch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return AppShadDialog(
      title: const Text('切换网关'),
      description: const Text('选择要连接的远程存储网关。'),
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final p in profiles) _row(context, theme, p)],
        ),
      ),
    );
  }

  Widget _row(BuildContext ctx, ShadThemeData theme, ProfileInfo profile) {
    final active = profile.name == activeProfile;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: active
            ? null
            : () {
                Navigator.of(ctx).pop();
                onSwitch(profile.name);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                active ? LucideIcons.radioReceiver : LucideIcons.server,
                size: 16,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 10),
              Text(
                profile.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.foreground,
                ),
              ),
              const Spacer(),
              if (active)
                Icon(
                  LucideIcons.check,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
