// 更新检查区：在通用设置中展示版本状态，并提供 GitHub 下载页入口。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/services/app_update_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsUpdateSection extends StatefulWidget {
  const SettingsUpdateSection({
    super.key,
    required this.theme,
    required this.currentVersion,
    this.updateService,
  });

  final ShadThemeData theme;
  final String currentVersion;
  final AppUpdateService? updateService;

  @override
  State<SettingsUpdateSection> createState() => _SettingsUpdateSectionState();
}

class _SettingsUpdateSectionState extends State<SettingsUpdateSection> {
  late final AppUpdateService _updateService;
  late final bool _ownsUpdateService;
  AppUpdateCheckResult? _result;
  String? _errorText;
  bool _checking = false;
  bool _openingDownloadPage = false;

  @override
  void initState() {
    super.initState();
    _updateService = widget.updateService ?? AppUpdateService();
    _ownsUpdateService = widget.updateService == null;
  }

  @override
  void dispose() {
    if (_ownsUpdateService) {
      _updateService.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UpdateStatusRow(
          theme: theme,
          title: _statusTitle,
          subtitle: _statusSubtitle,
          highlighted: _result?.updateAvailable == true,
          errorText: _errorText,
          checking: _checking,
          openingDownloadPage: _openingDownloadPage,
          onCheckForUpdates: _checking ? null : _checkForUpdates,
          onOpenDownloadPage: _openingDownloadPage ? null : _openDownloadPage,
        ),
      ],
    );
  }

  String get _statusTitle {
    final result = _result;
    if (_checking) {
      return '正在连接 GitHub';
    }
    if (result == null) {
      return '当前版本 ${widget.currentVersion}';
    }
    if (!result.comparable) {
      return '最新发布版本 ${result.latestVersion}';
    }
    if (result.updateAvailable) {
      return '发现新版本 ${result.latestVersion}';
    }
    return '当前已是最新版本';
  }

  String get _statusSubtitle {
    final result = _result;
    if (_checking) {
      return '正在读取 GitHub 最新 Release 信息。';
    }
    if (result == null) {
      return '检测 GitHub Release 是否有可用的新版本，也可以直接打开下载页。';
    }
    if (!result.comparable) {
      return '本地版本 ${result.currentVersion} 无法自动比较，可打开下载页查看是否需要更新。';
    }
    if (result.updateAvailable) {
      return '本地版本 ${result.currentVersion}，可前往 GitHub Release 下载更新。';
    }
    return '本地版本 ${result.currentVersion}，GitHub 最新发布版本 ${result.latestVersion}。';
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _errorText = null;
    });
    try {
      final result = await _updateService.checkLatestRelease(
        currentVersion: widget.currentVersion,
      );
      if (!mounted) {
        return;
      }
      setState(() => _result = result);
    } on TimeoutException {
      _showError('连接 GitHub 超时，请稍后重试。');
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _openDownloadPage() async {
    setState(() {
      _openingDownloadPage = true;
      _errorText = null;
    });
    try {
      final target = _result?.releaseUrl ?? kAppLatestReleasePageUrl;
      final launched = await launchUrl(
        Uri.parse(target),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!launched) {
        _showError('无法打开 GitHub 下载页。');
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _openingDownloadPage = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _errorText = message);
  }
}

class _UpdateStatusRow extends StatelessWidget {
  const _UpdateStatusRow({
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.highlighted,
    required this.errorText,
    required this.checking,
    required this.openingDownloadPage,
    required this.onCheckForUpdates,
    required this.onOpenDownloadPage,
  });

  final ShadThemeData theme;
  final String title;
  final String subtitle;
  final bool highlighted;
  final String? errorText;
  final bool checking;
  final bool openingDownloadPage;
  final VoidCallback? onCheckForUpdates;
  final VoidCallback? onOpenDownloadPage;

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
      ],
    );
  }

  Widget _buildActions(WrapAlignment alignment) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: alignment,
      children: [
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
        ShadButton(
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
