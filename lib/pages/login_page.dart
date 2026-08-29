// Browser login page gates access behind the configured WebDAV credentials.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/app/app_brand.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/app_brand_mark.dart';
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
      if (!mounted) return;
      widget.onLoggedIn();
    } catch (error) {
      if (!mounted) return;
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
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
      body: isAndroid ? _buildAndroidBody(theme) : _buildDesktopBody(theme),
    );
  }

  Widget _buildAndroidBody(ShadThemeData theme) {
    return Container(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MobileLoginOptions(theme: theme),
                  const SizedBox(height: 24),
                  _LoginForm(
                    theme: theme,
                    usernameController: _usernameController,
                    passwordController: _passwordController,
                    errorText: _errorText,
                    submitting: _submitting,
                    onSubmit: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopBody(ShadThemeData theme) {
    return Row(
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
                  child: _LoginForm(
                    theme: theme,
                    usernameController: _usernameController,
                    passwordController: _passwordController,
                    errorText: _errorText,
                    submitting: _submitting,
                    onSubmit: _submit,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileLoginOptions extends StatelessWidget {
  const _MobileLoginOptions({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final accent = ThemeController.of(context).accent;
    final accentColor = accent.color;
    final muted = theme.colorScheme.mutedForeground;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(const Color(0xffeef3ff), accentColor, 0.08)!,
            Color.lerp(const Color(0xfff8faff), accentColor, 0.03)!,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppBrandMark(height: 38, width: 180),
            const SizedBox(height: 14),
            Text(
              appBrandTagline,
              style: TextStyle(
                color: Color.lerp(const Color(0xff1e293b), accentColor, 0.15),
                fontSize: 20,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appBrandDescription,
              style: TextStyle(color: muted, fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 14),
            Text(
              '主题色',
              style: TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const _MobileAccentPicker(),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 13, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '凭证仅保存在本地',
                    style: TextStyle(color: muted, fontSize: 11.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileAccentPicker extends StatelessWidget {
  const _MobileAccentPicker();

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final preset in AccentPreset.values)
          _MobileAccentDot(
            preset: preset,
            isSelected: controller.accent == preset,
            onTap: () => controller.onAccentChanged(preset),
          ),
      ],
    );
  }
}

class _MobileAccentDot extends StatelessWidget {
  const _MobileAccentDot({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final AccentPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: preset.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: preset.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.65),
              width: isSelected ? 3 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: preset.color.withValues(
                  alpha: isSelected ? 0.35 : 0.12,
                ),
                blurRadius: isSelected ? 9 : 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.theme,
    required this.usernameController,
    required this.passwordController,
    required this.errorText,
    required this.submitting,
    required this.onSubmit,
  });

  final ShadThemeData theme;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final String? errorText;
  final bool submitting;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        Text(
          'WebDAV 账号',
          style: TextStyle(
            color: theme.colorScheme.foreground,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        ShadInput(
          controller: usernameController,
          placeholder: const Text('输入登录账号'),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 18),
        Text(
          'WebDAV 密码',
          style: TextStyle(
            color: theme.colorScheme.foreground,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        ShadInput(
          controller: passwordController,
          placeholder: const Text('输入登录密码'),
          obscureText: true,
          onSubmitted: (_) => onSubmit(),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.destructive.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.destructive.withValues(alpha: 0.15),
              ),
            ),
            child: Text(
              errorText!,
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
            onPressed: submitting ? null : onSubmit,
            child: submitting
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: AppLoadingIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primaryForeground,
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
    );
  }
}
