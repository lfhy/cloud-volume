// Desktop context menu wrapper centralizes right-click positioning and group dismissal.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DesktopContextMenuRegistry {
  static final Map<Object, ShadContextMenuController> _activeControllers =
      <Object, ShadContextMenuController>{};

  static bool dismiss(Object groupId) {
    final controller = _activeControllers[groupId];
    if (controller == null || !controller.isOpen) {
      return false;
    }
    controller.hide();
    _activeControllers.remove(groupId);
    return true;
  }

  static void activate(Object groupId, ShadContextMenuController controller) {
    final active = _activeControllers[groupId];
    if (!identical(active, controller)) {
      active?.hide();
      _activeControllers[groupId] = controller;
    }
  }

  static void deactivate(Object groupId, ShadContextMenuController controller) {
    if (identical(_activeControllers[groupId], controller)) {
      _activeControllers.remove(groupId);
    }
  }
}

class DesktopContextMenuHandle extends ChangeNotifier {
  Offset? _globalPosition;
  Offset? _menuOffset;

  Offset? get globalPosition => _globalPosition;
  Offset? get menuOffset => _menuOffset;

  void showAt(Offset globalPosition, {Offset? menuOffset}) {
    _globalPosition = globalPosition;
    _menuOffset = menuOffset;
    notifyListeners();
  }
}

class DesktopContextMenuRegion extends StatefulWidget {
  const DesktopContextMenuRegion({
    super.key,
    required this.groupId,
    required this.items,
    required this.child,
    this.menuOffset = const Offset(96, 4),
    this.constraints = const BoxConstraints(minWidth: 164),
    this.handle,
    this.captureSecondaryTap = true,
    this.onSecondaryTapDown,
  });

  final Object groupId;
  final List<Widget> items;
  final Widget child;
  final Offset menuOffset;
  final BoxConstraints constraints;
  final DesktopContextMenuHandle? handle;
  final bool captureSecondaryTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<DesktopContextMenuRegion> createState() =>
      _DesktopContextMenuRegionState();
}

class _DesktopContextMenuRegionState extends State<DesktopContextMenuRegion> {
  late final ShadContextMenuController _controller;
  Offset? _menuAnchorOffset;

  @override
  void initState() {
    super.initState();
    _controller = ShadContextMenuController();
    _controller.addListener(_syncActiveController);
    widget.handle?.addListener(_showFromHandle);
  }

  @override
  void didUpdateWidget(covariant DesktopContextMenuRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle != widget.handle) {
      oldWidget.handle?.removeListener(_showFromHandle);
      widget.handle?.addListener(_showFromHandle);
    }
  }

  @override
  void dispose() {
    widget.handle?.removeListener(_showFromHandle);
    _controller.removeListener(_syncActiveController);
    DesktopContextMenuRegistry.deactivate(widget.groupId, _controller);
    _controller.dispose();
    super.dispose();
  }

  void _syncActiveController() {
    if (_controller.isOpen) {
      DesktopContextMenuRegistry.activate(widget.groupId, _controller);
      return;
    }
    DesktopContextMenuRegistry.deactivate(widget.groupId, _controller);
  }

  void _showAt(Offset globalPosition, {Offset? menuOffset}) {
    if (!mounted) return;
    setState(
      () => _menuAnchorOffset =
          globalPosition + (menuOffset ?? widget.menuOffset),
    );
    _controller.show();
  }

  void _showFromHandle() {
    final globalPosition = widget.handle?.globalPosition;
    if (globalPosition == null) {
      return;
    }
    _showAt(globalPosition, menuOffset: widget.handle?.menuOffset);
  }

  @override
  Widget build(BuildContext context) {
    return ShadContextMenu(
      anchor: _menuAnchorOffset == null
          ? null
          : ShadGlobalAnchor(_menuAnchorOffset!),
      controller: _controller,
      constraints: widget.constraints,
      effects: const [],
      popoverReverseDuration: Duration.zero,
      items: widget.items,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: widget.captureSecondaryTap
            ? (details) {
                widget.onSecondaryTapDown?.call(details);
                _showAt(details.globalPosition);
              }
            : null,
        // The shared file browsers use this desktop context menu for actions.
        // Long press gives touch devices the same command set without a second
        // row renderer or a platform-only action sheet.
        onLongPressStart: widget.items.isEmpty
            ? null
            : (details) => _showAt(details.globalPosition),
        onTapDown: (_) {
          DesktopContextMenuRegistry.dismiss(widget.groupId);
        },
        child: widget.child,
      ),
    );
  }
}
