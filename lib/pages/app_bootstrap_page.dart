// 启动引导页：判断是否已有配置，决定跳转配置页还是主界面。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/services/cache_maintenance_service.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/pages/config_setup_page.dart';
import 'package:remote_storage/pages/login_page.dart';
import 'package:remote_storage/pages/main_layout_page.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/services/desktop_window_method_host.dart';
import 'package:remote_storage/services/app_exit_cleanup.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/app_log.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';

class AppBootstrapPage extends StatefulWidget {
  const AppBootstrapPage({super.key, required this.apiFactory});

  final RemoteStorageApiFactory apiFactory;

  @override
  State<AppBootstrapPage> createState() => _AppBootstrapPageState();
}

class _AppBootstrapPageState extends State<AppBootstrapPage> {
  _BootstrapSession? _session;
  Object? _loadError;
  bool _loading = true;
  bool _showSetupAnyway = false;
  bool _orphanSweepStarted = false;
  SidebarItem _selectedSidebarItem = SidebarItem.fileManager;

  @override
  void initState() {
    super.initState();
    DesktopWindowMethodHost.ensureInstalled();
    reconcileModalOverlayWithOpenChildren();
    unawaited(_loadSession(showLoadingShell: true));
  }

  Future<void> _loadSession({required bool showLoadingShell}) async {
    if (showLoadingShell) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    } else {
      setState(() {
        _showSetupAnyway = false;
        _loadError = null;
      });
    }

    try {
      final previous = _session;
      final _BootstrapSession session;
      if (previous == null) {
        final api = await widget.apiFactory();
        await AppLog.bind(api);
        final auth = await api.loadAuthSession();
        final state = await api.loadBootstrapState();
        session = _BootstrapSession(api: api, state: state, auth: auth);
      } else {
        // Soft refresh reuses the connected API so account reorder / settings
        // saves only replace bootstrap data without unmounting the main shell.
        final auth = await previous.api.loadAuthSession();
        final state = await previous.api.loadBootstrapState();
        session = _BootstrapSession(
          api: previous.api,
          state: state,
          auth: auth,
        );
      }
      if (!mounted) return;
      AppExitCleanup.register(session.api);
      // Best-effort orphan-mount sweep on the first session only: a previous
      // crashed run can leave a managed WebDAV mount on a dead loopback port.
      // Later soft refreshes skip it so a concurrent fresh mount is never
      // mistaken for an orphan while its server is still starting.
      if (!_orphanSweepStarted) {
        _orphanSweepStarted = true;
        unawaited(_sweepOrphanMounts(session.api));
      }
      setState(() {
        _session = session;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      // First launch still needs the error shell; later soft reloads keep the
      // current page so drag-reorder and settings saves do not flash.
      if (_session == null) {
        setState(() {
          _loading = false;
          _loadError = error;
        });
      }
    }
  }

  void _reload() {
    unawaited(_loadSession(showLoadingShell: _session == null));
  }

  Future<void> _sweepOrphanMounts(RemoteStorageGateway api) async {
    try {
      await api.sweepOrphanMounts().timeout(const Duration(seconds: 30));
    } catch (error) {
      // Startup must proceed even when a stale mount cannot be unmounted, but
      // leave a trace so the bridge log can be correlated with the UI failure.
      debugPrint('orphan mount sweep failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _session == null) {
      return const _BootstrapMessageView(
        title: '正在检查配置',
        description: '正在读取默认配置文件并准备远程存储环境。',
        loading: true,
      );
    }

    if (_loadError != null && _session == null) {
      return _BootstrapMessageView(
        title: '启动失败',
        description: describeBridgeError(_loadError!),
        actionLabel: '重试',
        onAction: _reload,
      );
    }

    final session = _session!;
    CacheMaintenanceService.instance.configure(
      session.api,
      session.state.config,
    );
    final shouldShowSetup = _showSetupAnyway || !session.state.configured;
    if (shouldShowSetup) {
      return ConfigSetupPage(
        api: session.api,
        initialState: session.state,
        onSaved: _reload,
      );
    }

    if (session.api.capabilities.supportsSessionLogin &&
        session.auth.loginRequired &&
        !session.auth.authenticated) {
      return LoginPage(
        api: session.api,
        configPath: session.state.configPath,
        onLoggedIn: _reload,
      );
    }

    return MainLayoutPage(
      state: session.state,
      api: session.api,
      selectedItem: _selectedSidebarItem,
      onSelectedItemChanged: (item) =>
          setState(() => _selectedSidebarItem = item),
      onEditConfig: () => setState(() => _showSetupAnyway = true),
      onRefresh: _reload,
    );
  }
}

class _BootstrapSession {
  const _BootstrapSession({
    required this.api,
    required this.state,
    required this.auth,
  });

  final RemoteStorageGateway api;
  final BootstrapState state;
  final AuthSessionState auth;
}

class _BootstrapMessageView extends StatelessWidget {
  const _BootstrapMessageView({
    required this.title,
    required this.description,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String description;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Center(
          child: ShadCard(
            width: 360,
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            title: Text(title),
            description: Text(
              description,
              style: TextStyle(
                color: theme.colorScheme.mutedForeground.withValues(alpha: 0.9),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: AppLoadingIndicator(strokeWidth: 2),
                    ),
                  ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ShadButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
