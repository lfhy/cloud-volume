// 启动引导页：判断是否已有配置，决定跳转配置页还是主界面。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/pages/config_setup_page.dart';
import 'package:remote_storage/pages/login_page.dart';
import 'package:remote_storage/pages/main_layout_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';

class AppBootstrapPage extends StatefulWidget {
  const AppBootstrapPage({super.key, required this.apiFactory});

  final RemoteStorageApiFactory apiFactory;

  @override
  State<AppBootstrapPage> createState() => _AppBootstrapPageState();
}

class _AppBootstrapPageState extends State<AppBootstrapPage> {
  late Future<_BootstrapSession> _sessionFuture;
  bool _showSetupAnyway = false;
  SidebarItem _selectedSidebarItem = SidebarItem.fileManager;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _loadSession();
  }

  Future<_BootstrapSession> _loadSession() async {
    final api = await widget.apiFactory();
    final auth = await api.loadAuthSession();
    final state = await api.loadBootstrapState();
    return _BootstrapSession(api: api, state: state, auth: auth);
  }

  void _reload() {
    setState(() {
      _showSetupAnyway = false;
      _sessionFuture = _loadSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapSession>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _BootstrapMessageView(
            title: '正在检查配置',
            description: '正在读取默认配置文件并准备远程存储环境。',
            loading: true,
          );
        }

        if (snapshot.hasError) {
          return _BootstrapMessageView(
            title: '启动失败',
            description: describeBridgeError(snapshot.error!),
            actionLabel: '重试',
            onAction: _reload,
          );
        }

        final session = snapshot.data!;
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
      },
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
