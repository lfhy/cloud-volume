// 更新检查区：在通用设置中展示版本状态，并提供 GitHub 下载页入口。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/services/app_installer.dart';
import 'package:remote_storage/services/app_update_service.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/services/proxy_http_client.dart';
import 'package:remote_storage/services/platform_asset_matcher.dart';
import 'package:remote_storage/services/update_settings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/widgets/settings_update_mirror_field.dart'
    show SettingsUpdateMirrorField;
import 'package:remote_storage/widgets/update_status_row.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsUpdateSection extends StatefulWidget {
  const SettingsUpdateSection({
    super.key,
    required this.theme,
    required this.currentVersion,
    this.config,
    this.updateService,
    this.api,
  });

  final ShadThemeData theme;
  final String currentVersion;
  final RemoteStorageConfig? config;
  final AppUpdateService? updateService;
  final RemoteStorageGateway? api;

  @override
  State<SettingsUpdateSection> createState() => _SettingsUpdateSectionState();
}

class _SettingsUpdateSectionState extends State<SettingsUpdateSection> {
  late final AppUpdateService _updateService;
  late final bool _ownsUpdateService;
  AppUpdateCheckResult? _result;
  // Matched asset from the Go bridge; null when no platform package exists.
  PlatformUpdateAsset? _matchedAsset;
  String? _errorText;
  bool _checking = false;
  bool _openingDownloadPage = false;
  bool _installing = false;
  double _installProgress = 0; // 0..1
  String _installStatusText = '';
  UpdateNetworkConfig _mirrorConfig = const UpdateNetworkConfig();
  // Compile-time architecture reported by the Go bridge; empty until loaded.
  String _buildArch = '';
  // Task id of the in-flight app update, projected by RemoteTaskStore.
  String? _installTaskId;

  @override
  void initState() {
    super.initState();
    _updateService = widget.updateService ?? AppUpdateService();
    _ownsUpdateService = widget.updateService == null;
    _loadMirrorConfig();
    _loadBuildArch();
    if (widget.api != null) RemoteTaskStore.instance.bindApi(widget.api!);
    RemoteTaskStore.instance.addListener(_onTransferQueueChanged);
  }

  /// Prefer the architecture injected into the Go bridge at build time. Falls
  /// back to a runtime heuristic when the bridge is unavailable (web, dev).
  Future<void> _loadBuildArch() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final info = await api.getBuildInfo();
      final arch = info.buildArch.isNotEmpty
          ? info.buildArch
          : info.runtimeArch;
      if (!mounted) return;
      if (arch.isNotEmpty) setState(() => _buildArch = arch);
    } catch (_) {
      // Non-fatal: matchPlatformAsset falls back to runtime detection.
    }
  }

  Future<void> _loadMirrorConfig() async {
    final config = await loadUpdateNetworkConfig();
    if (!mounted) return;
    setState(() => _mirrorConfig = config);
  }

  /// Asks the Go bridge to pick the correct asset for this platform. The Go
  /// side owns the release-asset name suffixes (synced with build scripts) so
  /// the frontend never guesses which file to download.
  Future<void> _resolveMatchedAsset(List<ReleaseAsset> assets) async {
    final api = widget.api;
    if (api == null || !kSupportsInAppInstall) return;
    try {
      final payload = await api.matchPlatformAsset(
        assets.map((a) => a.toJson()).toList(),
        runtimeArchitecture: _buildArch.isNotEmpty ? _buildArch : null,
      );
      if (!mounted) return;
      final matched = PlatformUpdateAsset.fromBridgeJson(payload);
      setState(() => _matchedAsset = matched);
    } catch (_) {
      // Non-fatal: the "一键更新" button stays hidden.
    }
  }

  @override
  void dispose() {
    RemoteTaskStore.instance.removeListener(_onTransferQueueChanged);
    if (_ownsUpdateService) {
      _updateService.close();
    }
    super.dispose();
  }

  void _onTransferQueueChanged() {
    final taskId = _installTaskId;
    if (taskId == null || !_installing) return;
    final id = taskId.startsWith('transfer:') ? taskId : 'transfer:$taskId';
    final task = RemoteTaskStore.instance.tasks.cast<RemoteTask?>().firstWhere(
      (t) => t?.id == id,
      orElse: () => null,
    );
    if (task == null) return;

    if (task.status == RemoteTaskStatus.done || task.phaseDetail == 'done') {
      if (mounted) {
        setState(() {
          _installStatusText = '安装完成，正在重启...';
          _installProgress = 1;
        });
      }
      return;
    }
    if (task.status == RemoteTaskStatus.canceled) {
      if (mounted) {
        setState(() {
          _resetInstallState();
          _errorText = null;
        });
      }
      return;
    }
    if (task.status == RemoteTaskStatus.failed) {
      final errMsg = task.error.isEmpty
          ? '更新失败，请重试或前往 GitHub 手动下载。'
          : task.error;
      if (mounted) {
        setState(() {
          _installing = false;
          _installTaskId = null;
          _installProgress = 0;
          _installStatusText = '';
          _errorText = errMsg;
        });
      }
      return;
    }
    final total = task.progress.totalBytes;
    final received = task.progress.bytesCompleted;
    final detail = task.phaseDetail;
    if (mounted) {
      setState(() {
        if (total > 0) {
          _installProgress = (received / total).clamp(0.0, 1.0);
        } else {
          _installProgress = -1;
        }
        if (detail == 'installing') {
          _installStatusText = '下载完成，正在安装...';
        } else if (detail == 'cached') {
          _installStatusText = '已命中本地更新包缓存，跳过下载...';
        } else if (total > 0) {
          _installStatusText =
              '正在下载 ${_formatBytes(received)} / ${_formatBytes(total)}';
        } else {
          _installStatusText = '正在下载 ${_formatBytes(received)}...';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UpdateStatusRow(
          theme: theme,
          title: _statusTitle,
          subtitle: _statusSubtitle,
          highlighted: _result?.updateAvailable == true,
          errorText: _errorText,
          checking: _checking,
          openingDownloadPage: _openingDownloadPage,
          installing: _installing,
          installProgress: _installProgress,
          canInstallInApp: _canInstallInApp,
          onCheckForUpdates: _checking ? null : _checkForUpdates,
          onOpenDownloadPage: _openingDownloadPage ? null : _openDownloadPage,
          onInstall: (_installing || !_canInstallInApp) ? null : _startInstall,
          canCancelInstall: _canCancelInstall,
          onCancelInstall: _canCancelInstall ? _cancelInstall : null,
        ),
        const SizedBox(height: 14),
        SettingsUpdateMirrorField(
          theme: theme,
          initialConfig: _mirrorConfig,
          onSaved: (config) {
            setState(() => _mirrorConfig = config);
          },
        ),
      ],
    );
  }

  /// Whether the current release has a platform-matched asset for auto-install.
  bool get _canInstallInApp {
    final result = _result;
    if (result == null || !result.updateAvailable) return false;
    if (!kSupportsInAppInstall) return false;
    return _matchedAsset != null;
  }

  ProxyConfig get _proxyConfig => ProxyConfig(
    mode: widget.config?.proxyMode ?? kProxyModeSystem,
    type: widget.config?.proxyType ?? kProxyTypeHttp,
    host: widget.config?.proxyHost ?? '',
    port: widget.config?.proxyPort ?? '',
    username: widget.config?.proxyUsername ?? '',
    password: widget.config?.proxyPassword ?? '',
  );

  Future<ProxyConfig> _resolveEffectiveProxy() async {
    final base = _proxyConfig;
    if (base.mode != kProxyModeSystem && base.mode.isNotEmpty) {
      return base;
    }
    final api = widget.api;
    if (api == null) {
      return base;
    }
    try {
      final info = await api.resolveSystemProxy();
      if (info != null && info.host.isNotEmpty) {
        return ProxyConfig(
          mode: kProxyModeCustom,
          type: info.type == 'socks5' ? kProxyTypeSocks5 : kProxyTypeHttp,
          host: info.host,
          port: info.port,
        );
      }
    } catch (_) {
      // Bridge unavailable or not supported: fall back to env-var detection.
    }
    return base;
  }

  Future<void> _startInstall() async {
    final api = widget.api;
    final result = _result;
    if (api == null || result == null) return;
    // Use the asset resolved by the Go bridge when the release was fetched.
    final matched = _matchedAsset;
    if (matched == null) {
      _showError('未找到适合当前平台的安装包，请前往 GitHub 手动下载。');
      return;
    }

    if (RemoteTaskStore.instance.hasActiveFileTransfers) {
      setState(() {
        _installing = true;
        _installProgress = -1;
        _installStatusText = '等待当前上传/下载任务完成...';
        _errorText = null;
      });
      await _waitForFileTransfersIdle();
      if (!mounted) return;
    }

    setState(() {
      _installing = true;
      _installProgress = -1;
      _installStatusText = '正在启动更新任务...';
      _errorText = null;
    });

    try {
      final proxyConfig = await _resolveEffectiveProxy();
      final taskId = await downloadAndInstallAsset(
        api,
        matched.asset,
        matched.installerType,
        networkConfig: _mirrorConfig,
        proxyConfig: proxyConfig,
        config: widget.config,
      );
      if (!mounted) return;
      setState(() {
        _installTaskId = taskId;
        _installStatusText = '正在下载 ${matched.asset.name}...';
      });
      unawaited(RemoteTaskStore.instance.refresh());
    } catch (error) {
      if (!mounted) return;
      _resetInstallState();
      _showError(error.toString());
    }
  }

  void _resetInstallState() {
    _installing = false;
    _installTaskId = null;
    _installProgress = 0;
    _installStatusText = '';
  }

  Future<void> _waitForFileTransfersIdle() async {
    final store = RemoteTaskStore.instance;
    if (!store.hasActiveFileTransfers) return;
    final completer = Completer<void>();
    void listener() {
      if (!store.hasActiveFileTransfers) {
        store.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    }

    store.addListener(listener);
    try {
      await completer.future;
    } finally {
      store.removeListener(listener);
    }
  }

  bool get _canCancelInstall => _installing;

  Future<void> _cancelInstall() async {
    if (_installTaskId == null && _installing) {
      if (mounted) {
        setState(() {
          _resetInstallState();
          _errorText = null;
        });
      }
      return;
    }
    final taskId = _installTaskId;
    if (taskId == null) return;
    setState(() => _installStatusText = '正在取消更新...');
    try {
      final id = taskId.startsWith('transfer:') ? taskId : 'transfer:$taskId';
      await RemoteTaskStore.instance.cancel(id);
    } catch (error) {
      if (!mounted) return;
      _showError('取消更新失败：$error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _resetInstallState();
      _errorText = null;
    });
    await RemoteTaskStore.instance.refresh();
  }

  String get _statusTitle {
    final result = _result;
    if (_checking) {
      return '正在连接 GitHub';
    }
    if (_installing) {
      if (_installProgress < 0) {
        return '正在下载安装包';
      }
      final pct = (_installProgress * 100).clamp(0, 100).toInt();
      return _installProgress >= 1 ? '正在安装新版本...' : '正在下载 $pct%';
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
    if (_installing) {
      return _installStatusText.isEmpty
          ? '请稍候，更新过程中应用将自动重启。'
          : _installStatusText;
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
      final proxyConfig = await _resolveEffectiveProxy();
      final result = await _updateService.checkLatestRelease(
        currentVersion: widget.currentVersion,
        networkConfig: _mirrorConfig,
        proxyConfig: proxyConfig,
      );
      if (!mounted) {
        return;
      }
      setState(() => _result = result);
      // Ask the Go bridge which asset to download; it owns the name suffixes.
      _resolveMatchedAsset(result.assets);
    } on TimeoutException {
      _showError(
        '连接 GitHub 超时（已自动重试）。请检查网络或代理设置，'
        '安装包下载可在下方配置 GitHub 加速镜像后重试一键更新。',
      );
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

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
