// Browser login page gates web access behind the configured WebDAV credentials.

import 'package:flutter/material.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/config_left_panel.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.api,
    required this.onLoggedIn,
    required this.configPath,
  });

  final RemoteStorageGateway api;
  final VoidCallback onLoggedIn;
  final String configPath;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorText = '请输入 WebDAV 账号和密码。');
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await widget.api.login(username, password);
      if (!mounted) {
        return;
      }
      widget.onLoggedIn();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorText = describeBridgeError(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      body: Row(
        children: [
          Expanded(child: ConfigLeftPanel(configPath: widget.configPath)),
          Expanded(
            child: Container(
              color: theme.colorScheme.background,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '登录 Web 控制台',
                          style: theme.textTheme.h3.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '默认使用当前 AK/SK 登录当前控制台；如果你在系统设置里改过 WebDAV 凭据，则这里使用修改后的账号密码。',
                          style: TextStyle(
                            color: theme.colorScheme.mutedForeground,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _fieldLabel(context, 'WebDAV 账号'),
                        const SizedBox(height: 6),
                        ShadInput(
                          controller: _usernameController,
                          placeholder: const Text('输入登录账号'),
                        ),
                        const SizedBox(height: 18),
                        _fieldLabel(context, 'WebDAV 密码'),
                        const SizedBox(height: 6),
                        ShadInput(
                          controller: _passwordController,
                          placeholder: const Text('输入登录密码'),
                          obscureText: true,
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.destructive.withValues(
                                alpha: 0.06,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.destructive.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                            ),
                            child: Text(
                              _errorText!,
                              style: TextStyle(
                                color: theme.colorScheme.destructive,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 44,
                          child: ShadButton(
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: AppLoadingIndicator(
                                          strokeWidth: 2,
                                          color: theme.colorScheme
                                              .primaryForeground,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('登录中...'),
                                    ],
                                  )
                                : const Text('登录'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String text) {
    final theme = ShadTheme.of(context);
    return Text(
      text,
      style: TextStyle(
        color: theme.colorScheme.foreground,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
