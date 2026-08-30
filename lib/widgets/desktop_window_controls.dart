// Desktop chrome replaces the native title bar on Windows and Linux so the
// app can keep one consistent top-right control strip across desktop shells.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/window_controls.dart';
import 'package:remote_storage/services/app_exit_cleanup.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowControls extends StatefulWidget {
  const DesktopWindowControls({super.key});

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls>
    with WindowListener {
  bool _maximized = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshMaximized();
    // Route OS-level close gestures (Alt+F4 / taskbar close on Windows) through
    // the same confirmation flow as the in-app close button.
    WindowControls.registerCloseRequestHandler(_handleCloseRequest);
    WindowControls.registerExitRequestHandler(_handleExitRequest);
    if (isWindowsPlatform) windowManager.addListener(this);
  }

  @override
  void dispose() {
    WindowControls.registerCloseRequestHandler(null);
    WindowControls.registerExitRequestHandler(null);
    if (isWindowsPlatform) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  @override
  void onWindowRestore() => unawaited(_refreshMaximized());

  void _setMaximized(bool value) {
    if (mounted && _maximized != value) setState(() => _maximized = value);
  }

  Future<void> _handleCloseRequest() => _confirmClose();

  Future<void> _handleExitRequest() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await _hideAndCleanupThenExit();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hideAndCleanupThenExit() async {
    try {
      await WindowControls.hideForExit();
    } catch (_) {
      // Older hosts may not expose hideForExit; cleanup and exit still proceed.
    }
    await AppExitCleanup.cleanupMounts();
    await WindowControls.exitApp();
  }

  Future<void> _refreshMaximized() async {
    if (!WindowControls.supported) return;
    final maximized = await WindowControls.isMaximized();
    if (!mounted) return;
    setState(() => _maximized = maximized);
  }

  Future<void> _toggleMaximize() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final maximized = await WindowControls.toggleMaximize();
      if (!mounted) return;
      setState(() => _maximized = maximized);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmClose() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      final activeMountCount = await AppExitCleanup.activeMountCount();
      final hasActiveMounts = activeMountCount > 0;
      if (!mounted) return;
      final description = hasActiveMounts
          ? '当前有 $activeMountCount 个挂载。退出会卸载这些挂载；如需保留挂载，请选择“后台运行”。'
          : WindowControls.supportsTray
          ? '你可以隐藏到托盘，或者直接退出应用。'
          : '你可以先最小化窗口，或者直接退出应用。';
      final choice = await showAppModal<_CloseAction>(
        context: context,
        builder: (dialogContext) => AppShadDialog(
          title: const Text('关闭云卷？'),
          description: hasActiveMounts
              ? Text(description)
              : Text(
                  WindowControls.supportsTray
                      ? '你可以隐藏到托盘，或者直接退出应用。'
                      : '你可以先最小化窗口，或者直接退出应用。',
                ),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ShadButton.outline(
                        onPressed: () => Navigator.of(dialogContext).pop(
                          WindowControls.supportsTray
                              ? _CloseAction.tray
                              : _CloseAction.minimize,
                        ),
                        child: hasActiveMounts
                            ? const Text('后台运行')
                            : Text(
                                WindowControls.supportsTray
                                    ? '最小化到托盘'
                                    : '最小化窗口',
                              ),
                      ),
                      ShadButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(_CloseAction.exit),
                        child: const Text('退出云卷'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      switch (choice) {
        case _CloseAction.tray:
          await WindowControls.hideToTray();
          break;
        case _CloseAction.minimize:
          await WindowControls.minimize();
          break;
        case _CloseAction.exit:
          await _hideAndCleanupThenExit();
          break;
        case null:
          break;
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isWindowsPlatform && !isLinuxPlatform) {
      return const SizedBox.shrink();
    }

    final theme = ShadTheme.of(context);
    final border = theme.colorScheme.border.withValues(alpha: 0.7);
    final panel = theme.colorScheme.background.withValues(alpha: 0.82);

    return Positioned(
      top: 8,
      left: 0,
      right: 10,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanDown: (_) => unawaited(WindowControls.startDrag()),
              onDoubleTap: () => unawaited(_toggleMaximize()),
              child: const SizedBox(height: 48),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WindowButton(
                  tooltip: '最小化',
                  icon: LucideIcons.minus,
                  onPressed: () => unawaited(WindowControls.minimize()),
                ),
                _WindowButton(
                  tooltip: _maximized ? '还原' : '最大化',
                  icon: _maximized ? LucideIcons.copy : LucideIcons.square,
                  onPressed: () => unawaited(_toggleMaximize()),
                ),
                _WindowButton(
                  tooltip: '关闭',
                  icon: LucideIcons.x,
                  destructive: true,
                  onPressed: () => unawaited(_confirmClose()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CloseAction { tray, minimize, exit }

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = widget.destructive
        ? const Color(0xffb42318)
        : theme.colorScheme.foreground;
    final background = widget.destructive
        ? const Color(0xfffef3f2)
        : theme.colorScheme.secondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 42,
            height: 36,
            decoration: BoxDecoration(
              color: _hovered ? background : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 16, color: foreground),
          ),
        ),
      ),
    );
  }
}
