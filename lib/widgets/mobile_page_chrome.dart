// Shared Android mobile-page chrome: a uniform header for top-level tab
// pages (large title + muted subtitle + one 48dp action entry) and the
// bottom action sheet opened from it. The file-manager keeps its own
// stateful header because it also owns back-stack handling; the action
// sheet below is the single shared implementation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/services/app_modal.dart';

/// One row inside a mobile action sheet.
class MobilePageAction {
  const MobilePageAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// Header for Android top-level tab pages: stable large title, one-line
/// subtitle, and a single 48dp entry that opens the action sheet. When
/// [actions] is empty the entry is hidden entirely.
class MobilePageHeader extends StatelessWidget {
  const MobilePageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const <MobilePageAction>[],
    this.actionSheetTitle,
    this.actionsSemanticLabel,
    this.actionIcon,
  });

  final String title;
  final String subtitle;
  final List<MobilePageAction> actions;
  final String? actionSheetTitle;
  final String? actionsSemanticLabel;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.h3.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 23,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.mutedForeground,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 8),
          Semantics(
            label: actionsSemanticLabel,
            child: ShadIconButton.ghost(
              width: 48,
              height: 48,
              iconSize: 22,
              icon: Icon(
                actionIcon ?? LucideIcons.plus,
                color: theme.colorScheme.primary,
              ),
              onPressed: () => unawaited(
                showMobileActionSheet(
                  context,
                  title: actionSheetTitle ?? title,
                  actions: actions,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Opens the shared bottom action sheet: full-width 48dp rows inside the
/// horizontal safe area, matching the file-manager drawer contract.
Future<void> showMobileActionSheet(
  BuildContext context, {
  required String title,
  required List<MobilePageAction> actions,
}) async {
  if (actions.isEmpty) return;
  await showAppModal<void>(
    context: context,
    builder: (dialogContext) {
      // Keep sheet rows full-width inside horizontal cutouts while matching
      // the 16dp icon inset used by bucket and object action drawers.
      final horizontalSafeArea = MediaQuery.paddingOf(dialogContext).horizontal;
      const actionHorizontalPadding = 16.0;
      final menuWidth =
          (MediaQuery.sizeOf(dialogContext).width - horizontalSafeArea - 60)
              .clamp(1.0, double.infinity)
              .toDouble();
      final actionContentWidth = (menuWidth - actionHorizontalPadding * 2)
          .clamp(0.0, double.infinity)
          .toDouble();
      return AppShadDialog(
        title: Text(title),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final action in actions) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: ShadButton.ghost(
                  width: menuWidth,
                  padding: const EdgeInsets.symmetric(
                    horizontal: actionHorizontalPadding,
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    action.onPressed();
                  },
                  child: SizedBox(
                    width: actionContentWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 48,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(action.icon, size: 17),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              action.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      );
    },
  );
}
