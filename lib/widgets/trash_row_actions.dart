// Trash row actions render the deleted-time column plus explicit recovery controls.

import 'package:flutter/material.dart';
import 'package:remote_storage/widgets/app_tooltip.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shared trailing cells for trash list rows.
class TrashRowActions extends StatelessWidget {
  const TrashRowActions({
    super.key,
    required this.deletedLabel,
    required this.busy,
    required this.onRestore,
    required this.onDeletePermanently,
  });

  static const double actionColumnWidth = 88;

  final String deletedLabel;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 154,
          child: Text(
            busy ? '处理中...' : deletedLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11.5,
              color: busy
                  ? theme.colorScheme.primary
                  : theme.colorScheme.mutedForeground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: actionColumnWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _TrashActionIcon(
                message: '恢复',
                icon: LucideIcons.rotateCcw,
                color: theme.colorScheme.primary,
                onPressed: busy ? null : onRestore,
              ),
              const SizedBox(width: 8),
              _TrashActionIcon(
                message: '彻底删除',
                icon: LucideIcons.trash2,
                color: theme.colorScheme.mutedForeground,
                onPressed: busy ? null : onDeletePermanently,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrashActionIcon extends StatelessWidget {
  const _TrashActionIcon({
    required this.message,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppTooltip(
      message: message,
      child: ShadIconButton.ghost(
        icon: Icon(icon, size: 14, color: color),
        width: 26,
        height: 26,
        iconSize: 14,
        onPressed: onPressed,
      ),
    );
  }
}
