// File manager empty state keeps blank bucket and directory views visually consistent.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerEmptyState extends StatelessWidget {
  const FileManagerEmptyState({
    super.key,
    required this.theme,
    required this.icon,
    required this.text,
  });

  final ShadThemeData theme;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 44,
            color: theme.colorScheme.mutedForeground.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
