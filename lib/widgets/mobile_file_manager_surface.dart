// Android file-manager surface: a touch-first shell and list renderer kept
// separate from the dense desktop table/grid widgets.

import 'package:flutter/material.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The Android file-manager chrome. The body is supplied by the page state so
/// loading/error/mutation behavior remains owned by the existing controller.
class MobileFileManagerSurface extends StatelessWidget {
  const MobileFileManagerSurface({
    super.key,
    required this.title,
    required this.subtitle,
    required this.searchController,
    required this.searchPlaceholder,
    required this.searchEnabled,
    required this.body,
    this.onBack,
    this.onSettings,
    this.onMore,
    this.onFab,
    this.showFab = true,
  });

  final String title;
  final String subtitle;
  final TextEditingController searchController;
  final String searchPlaceholder;
  final bool searchEnabled;
  final Widget body;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final VoidCallback? onMore;
  final VoidCallback? onFab;
  final bool showFab;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileFileManagerTopBar(
                  title: title,
                  subtitle: subtitle,
                  onBack: onBack,
                  onSettings: onSettings,
                  onMore: onMore,
                ),
                const SizedBox(height: 14),
                _MobileFileManagerSearchField(
                  controller: searchController,
                  placeholder: searchPlaceholder,
                  enabled: searchEnabled,
                ),
                const SizedBox(height: 12),
                Expanded(child: body),
              ],
            ),
            if (showFab && onFab != null)
              Positioned(
                right: 4,
                bottom: 18,
                child: _MobileFileManagerFab(onPressed: onFab!),
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileFileManagerTopBar extends StatelessWidget {
  const _MobileFileManagerTopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onSettings,
    required this.onMore,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (onBack != null) ...[
          _MobileIconButton(
            tooltip: '返回',
            icon: LucideIcons.chevronLeft,
            onPressed: onBack,
          ),
          const SizedBox(width: 2),
        ] else if (onSettings != null) ...[
          _MobileIconButton(
            tooltip: '设置',
            icon: LucideIcons.settings2,
            onPressed: onSettings,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.h3.copyWith(
                  fontSize: onBack == null ? 30 : 22,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onBack != null && onSettings != null) ...[
          const SizedBox(width: 4),
          _MobileIconButton(
            tooltip: '设置',
            icon: LucideIcons.settings2,
            onPressed: onSettings,
          ),
        ],
        if (onMore != null) ...[
          const SizedBox(width: 2),
          _MobileIconButton(
            tooltip: '更多操作',
            icon: LucideIcons.ellipsis,
            onPressed: onMore,
          ),
        ],
      ],
    );
  }
}

class _MobileFileManagerSearchField extends StatelessWidget {
  const _MobileFileManagerSearchField({
    required this.controller,
    required this.placeholder,
    required this.enabled,
  });

  final TextEditingController controller;
  final String placeholder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox(
      height: 48,
      child: ShadInput(
        controller: controller,
        enabled: enabled,
        placeholder: Text(placeholder),
        leading: Icon(
          LucideIcons.search,
          size: 19,
          color: theme.colorScheme.mutedForeground,
        ),
        trailing: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return AppTooltip(
              message: '清除搜索',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: controller.clear,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.x,
                    size: 17,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
            );
          },
        ),
        style: TextStyle(fontSize: 15, color: theme.colorScheme.foreground),
      ),
    );
  }
}

class _MobileIconButton extends StatelessWidget {
  const _MobileIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppTooltip(
      message: tooltip,
      child: ShadIconButton.ghost(
        width: 42,
        height: 42,
        iconSize: 21,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

class _MobileFileManagerFab extends StatelessWidget {
  const _MobileFileManagerFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return AppTooltip(
      message: '添加或上传',
      child: Material(
        color: Colors.transparent,
        elevation: 7,
        shadowColor: Colors.black.withValues(alpha: 0.24),
        shape: const CircleBorder(),
        child: Ink(
          width: 58,
          height: 58,
          decoration: ShapeDecoration(
            color: theme.colorScheme.primary,
            shape: const CircleBorder(),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const Icon(LucideIcons.plus, size: 31, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
