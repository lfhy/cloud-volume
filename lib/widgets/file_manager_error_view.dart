// File-manager error view keeps retry and reconfigure actions consistent while
// the page decides which recovery path should be exposed for the current state.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerErrorView extends StatelessWidget {
  const FileManagerErrorView({
    super.key,
    required this.theme,
    required this.message,
    required this.onRetry,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final ShadThemeData theme;
  final String message;
  final VoidCallback onRetry;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 40,
            color: theme.colorScheme.destructive,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              message,
              style: TextStyle(
                color: theme.colorScheme.destructive,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              ShadButton(onPressed: onRetry, child: const Text('重试')),
              if (secondaryActionLabel != null && onSecondaryAction != null)
                ShadButton.outline(
                  onPressed: onSecondaryAction,
                  child: Text(secondaryActionLabel!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
