// Pure presentation widget for the update status card (icon, copy, actions,
// progress bar). Extracted from settings_update_section.dart to keep that
// file under the repository 500-line ceiling.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class UpdateStatusRow extends StatelessWidget {
  const UpdateStatusRow({
    super.key,
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.highlighted,
    required this.errorText,
    required this.checking,
    required this.openingDownloadPage,
    required this.installing,
    required this.installProgress,
    required this.canInstallInApp,
    required this.canCancelInstall,
    required this.onCheckForUpdates,
    required this.onOpenDownloadPage,
    required this.onInstall,
    required this.onCancelInstall,
  });

  final ShadThemeData theme;
  final String title;
  final String subtitle;
  final bool highlighted;
  final String? errorText;
  final bool checking;
  final bool openingDownloadPage;
  final bool installing;
  final double installProgress;
  final bool canInstallInApp;
  final bool canCancelInstall;
  final VoidCallback? onCheckForUpdates;
  final VoidCallback? onOpenDownloadPage;
  final VoidCallback? onInstall;
  final VoidCallback? onCancelInstall;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            border: highlighted
                ? Border.all(color: theme.colorScheme.primary)
                : Border.all(color: Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: compact ? _buildCompactContent() : _buildWideContent(),
        );
      },
    );
  }

  Widget _buildWideContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildIcon(),
        const SizedBox(width: 12),
        Expanded(child: _buildCopy()),
        const SizedBox(width: 12),
        _buildActions(WrapAlignment.end),
      ],
    );
  }

  Widget _buildCompactContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIcon(),
            const SizedBox(width: 12),
            Expanded(child: _buildCopy()),
          ],
        ),
        const SizedBox(height: 12),
        _buildActions(WrapAlignment.start),
      ],
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : theme.colorScheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        highlighted ? LucideIcons.circleArrowUp : LucideIcons.badgeCheck,
        size: 18,
        color: highlighted
            ? theme.colorScheme.primary
            : theme.colorScheme.mutedForeground,
      ),
    );
  }

  Widget _buildCopy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
        if (installing) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              // null → indeterminate animation when total size is unknown.
              value: installProgress >= 0
                  ? installProgress.clamp(0.0, 1.0)
                  : null,
              backgroundColor: theme.colorScheme.background,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
              minHeight: 5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(WrapAlignment alignment) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: alignment,
      children: [
        if (installing && canCancelInstall)
          ShadButton(
            onPressed: canCancelInstall ? onCancelInstall : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.x, size: 15),
                const SizedBox(width: 8),
                const Text('取消更新'),
              ],
            ),
          ),
        if (!installing && canInstallInApp)
          ShadButton(
            onPressed: onInstall,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.download, size: 15),
                const SizedBox(width: 8),
                const Text('一键更新'),
              ],
            ),
          ),
        if (!installing)
          ShadButton.outline(
            onPressed: onCheckForUpdates,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.refreshCw, size: 15),
                const SizedBox(width: 8),
                Text(checking ? '检测中...' : '检测更新'),
              ],
            ),
          ),
        ShadButton.outline(
          onPressed: onOpenDownloadPage,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.externalLink, size: 15),
              const SizedBox(width: 8),
              Text(openingDownloadPage ? '打开中...' : 'GitHub 下载'),
            ],
          ),
        ),
      ],
    );
  }
}
