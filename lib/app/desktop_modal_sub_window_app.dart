// Generic modal sub-window shell. Encapsulates the boilerplate that was
// duplicated across account-editor, sync-editor, and directory-picker windows:
// ShadApp + theme, lifecycle (overlay release), focus gate, scrim, title bar,
// loading/error states, content padding, and the close-window sequence.
//
// Each feature supplies a [bootstrap] function (loads its bridge / data) and a
// [contentBuilder] that turns the bootstrapped value into a widget. The shell
// handles everything else identically.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/services/desktop_modal_overlay_controller.dart';
import 'package:remote_storage/services/desktop_sub_window_modal.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/widgets/desktop_modal_parent_focus_relay.dart';
import 'package:remote_storage/widgets/desktop_modal_scrim.dart';
import 'package:remote_storage/widgets/desktop_modal_shell.dart';
import 'package:remote_storage/widgets/desktop_modal_window_focus_gate.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

/// Runs a modal sub-window: ShadApp + theme + lifecycle + scrim + title bar +
/// bootstrap-driven content body.
///
/// [bootstrap] loads whatever the content needs (e.g. RemoteStorageGateway,
/// bucket list) and returns a value of type [T]. [contentBuilder] turns that
/// value into the body widget and receives a [close] callback to shut the
/// window (after optional [onClose]).
///
/// [scrollable] wraps content in [SingleChildScrollView] when true (good for
/// form-like content such as the account editor). Set false when the content
/// manages its own layout with [Expanded] / fill-height widgets (sync editor,
/// directory picker) — an outer scroll view would give unbounded height and
/// break those flex children.
///
/// [useParentFocusRelay] controls whether [DesktopModalParentFocusRelay] wraps
/// the content — account/sync editors use it, the picker does not.
class DesktopModalSubWindowApp<T> extends StatelessWidget {
  const DesktopModalSubWindowApp({
    required this.title,
    required this.creatorWindowId,
    required this.bootstrap,
    required this.contentBuilder,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 16, 24, 24),
    this.scrollable = true,
    this.useParentFocusRelay = true,
    this.onClose,
    super.key,
  });

  final String title;
  final String creatorWindowId;
  final Future<T> Function() bootstrap;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() close,
  ) contentBuilder;
  final EdgeInsets contentPadding;

  /// When true, content is wrapped in [SingleChildScrollView]. Default true.
  final bool scrollable;
  final bool useParentFocusRelay;

  /// Called after the user clicks close / window close event, before the
  /// window actually closes. Use this to send a result to the creator.
  final Future<void> Function()? onClose;

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: '云卷 - $title',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: buildAppTheme(AccentPreset.blue),
      home: _ModalSubWindowLifecycle(
        creatorWindowId: creatorWindowId,
        onClose: onClose,
        child: _maybeWrapFocusRelay(
          DesktopModalWindowFocusGate(
            child: Stack(
              children: [
                _ModalSubWindowBody<T>(
                  title: title,
                  creatorWindowId: creatorWindowId,
                  bootstrap: bootstrap,
                  contentBuilder: contentBuilder,
                  contentPadding: contentPadding,
                  scrollable: scrollable,
                  onClose: onClose,
                ),
                const DesktopModalScrim(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _maybeWrapFocusRelay(Widget child) {
    if (!useParentFocusRelay) return child;
    return DesktopModalParentFocusRelay(child: child);
  }
}

// ---------------------------------------------------------------------------
// Body: bootstrap → loading → error → content
// ---------------------------------------------------------------------------

class _ModalSubWindowBody<T> extends StatefulWidget {
  const _ModalSubWindowBody({
    required this.title,
    required this.creatorWindowId,
    required this.bootstrap,
    required this.contentBuilder,
    required this.contentPadding,
    required this.scrollable,
    required this.onClose,
  });

  final String title;
  final String creatorWindowId;
  final Future<T> Function() bootstrap;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() close,
  ) contentBuilder;
  final EdgeInsets contentPadding;
  final bool scrollable;
  final Future<void> Function()? onClose;

  @override
  State<_ModalSubWindowBody<T>> createState() => _ModalSubWindowBodyState<T>();
}

class _ModalSubWindowBodyState<T> extends State<_ModalSubWindowBody<T>> {
  T? _data;
  bool _loading = true;
  String? _error;

  Future<void> _close() => closeDesktopModalSubWindow(
        creatorWindowId: widget.creatorWindowId,
        onClose: widget.onClose,
      );

  @override
  void initState() {
    super.initState();
    _runBootstrap();
  }

  Future<void> _runBootstrap() async {
    try {
      final data = await widget.bootstrap();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Column(
        children: [
          DesktopModalShell(
            title: widget.title,
            onClose: () {
              _close();
            },
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ShadThemeData theme) {
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_error != null || _data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle,
                size: 40, color: theme.colorScheme.destructive),
            const SizedBox(height: 10),
            Text(_error ?? '初始化失败', style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
    }
    final content = widget.contentBuilder(context, _data as T, _close);
    // scrollable: form-like content (account editor) can grow past the window.
    // Non-scrollable: content owns Expanded/fill-height layout and needs a
    // finite height from this Expanded parent (sync editor, directory picker).
    if (widget.scrollable) {
      return Padding(
        padding: widget.contentPadding,
        child: SingleChildScrollView(child: content),
      );
    }
    return Padding(
      padding: widget.contentPadding,
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Lifecycle: releases parent overlay on dispose / window close
// ---------------------------------------------------------------------------

class _ModalSubWindowLifecycle extends StatefulWidget {
  const _ModalSubWindowLifecycle({
    required this.creatorWindowId,
    required this.onClose,
    required this.child,
  });

  final String creatorWindowId;
  final Future<void> Function()? onClose;
  final Widget child;

  @override
  State<_ModalSubWindowLifecycle> createState() =>
      _ModalSubWindowLifecycleState();
}

class _ModalSubWindowLifecycleState extends State<_ModalSubWindowLifecycle>
    with WindowListener {
  var _released = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _releaseParentOverlayOnce();
    super.dispose();
  }

  @override
  void onWindowClose() {
    _releaseParentOverlayOnce();
  }

  Future<void> _releaseParentOverlayOnce() async {
    if (_released) return;
    _released = true;
    final id = (await WindowController.fromCurrentEngine()).windowId;
    DesktopModalOverlayController.instance.unregisterChildWindow(id);
    await notifyCreatorModalOverlayRelease(widget.creatorWindowId);
    await clearModalChildWindowChrome();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------------------
// Shared close function (replaces _closeAccountEditorWindow etc.)
// ---------------------------------------------------------------------------

/// Runs the full modal-sub-window close sequence: optional [onClose] callback
/// (for sending results), then overlay release + chrome clear + window close.
Future<void> closeDesktopModalSubWindow({
  required String creatorWindowId,
  Future<void> Function()? onClose,
}) async {
  if (onClose != null) {
    await onClose();
  }
  final id = (await WindowController.fromCurrentEngine()).windowId;
  DesktopModalOverlayController.instance.unregisterChildWindow(id);
  await notifyCreatorModalOverlayRelease(creatorWindowId);
  await clearModalChildWindowChrome();
  await windowManager.close();
}
