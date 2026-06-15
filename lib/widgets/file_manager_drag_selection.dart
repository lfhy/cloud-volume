// Desktop drag selection keeps list and grid multi-select behavior in one reusable layer.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class FileManagerDragSelection extends StatefulWidget {
  const FileManagerDragSelection({
    super.key,
    required this.enabled,
    required this.selectedKeys,
    required this.onSelectionChanged,
    required this.child,
    this.onBlankTap,
    this.onBlankSecondaryTapDown,
  });

  final bool enabled;
  final Set<String> selectedKeys;
  final ValueChanged<Set<String>> onSelectionChanged;
  final Widget child;
  final VoidCallback? onBlankTap;
  final GestureTapDownCallback? onBlankSecondaryTapDown;

  @override
  State<FileManagerDragSelection> createState() =>
      _FileManagerDragSelectionState();
}

class _FileManagerDragSelectionState extends State<FileManagerDragSelection> {
  static const double _dragThreshold = 6;

  final Map<String, BuildContext> _targets = <String, BuildContext>{};
  final Set<BuildContext> _blankTapBlockers = <BuildContext>{};
  Set<String>? _dragBaseSelection;
  final Set<String> _dragTouchedKeys = <String>{};
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _trackingPrimaryPointer = false;
  bool _pointerStartedOnTarget = false;
  bool _dragging = false;

  void registerTarget(String key, BuildContext context) {
    _targets[key] = context;
  }

  void unregisterTarget(String key, BuildContext context) {
    final current = _targets[key];
    if (current == context) {
      _targets.remove(key);
    }
  }

  void registerBlankTapBlocker(BuildContext context) {
    _blankTapBlockers.add(context);
  }

  void unregisterBlankTapBlocker(BuildContext context) {
    _blankTapBlockers.remove(context);
  }

  @override
  Widget build(BuildContext context) {
    return _DragSelectionScope(
      state: this,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerEnd,
        onPointerCancel: _handlePointerCancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_dragging && _selectionRect != null)
              IgnorePointer(
                child: CustomPaint(
                  painter: _SelectionRectPainter(rect: _selectionRect!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    final local = _localPositionFor(event.position);
    if (local == null) {
      return;
    }
    final isBlank = !_hitsInteractiveRegion(local);
    if (event.buttons == kSecondaryMouseButton) {
      if (isBlank) {
        widget.onBlankSecondaryTapDown?.call(
          TapDownDetails(
            globalPosition: event.position,
            localPosition: local,
            kind: event.kind,
          ),
        );
      }
      return;
    }
    if (event.buttons != kPrimaryMouseButton) {
      return;
    }
    _dragStart = local;
    _dragCurrent = local;
    _dragBaseSelection = Set<String>.of(widget.selectedKeys);
    _dragTouchedKeys.clear();
    _trackingPrimaryPointer = true;
    _pointerStartedOnTarget = !isBlank;
    _dragging = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_dragStart == null || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    final local = _localPositionFor(event.position);
    if (local == null) {
      return;
    }
    _dragCurrent = local;
    if (!_dragging && (local - _dragStart!).distance >= _dragThreshold) {
      setState(() => _dragging = true);
    } else if (_dragging) {
      setState(() {});
    }
    if (_dragging) {
      _applySelection();
    }
  }

  void _handlePointerEnd(PointerUpEvent event) {
    if (!_trackingPrimaryPointer) {
      return;
    }
    if (_dragging) {
      _applySelection();
    } else if (!_pointerStartedOnTarget) {
      widget.onBlankTap?.call();
    }
    _resetDrag();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _resetDrag();
  }

  void _applySelection() {
    final selectionRect = _selectionRect;
    final regionBox = context.findRenderObject() as RenderBox?;
    if (selectionRect == null || regionBox == null) {
      return;
    }
    final selected = Set<String>.of(_dragBaseSelection ?? widget.selectedKeys);
    final baseSelection = _dragBaseSelection ?? widget.selectedKeys;
    for (final entry in _targets.entries) {
      final renderObject = entry.value.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) {
        continue;
      }
      final origin = renderObject.localToGlobal(
        Offset.zero,
        ancestor: regionBox,
      );
      final bounds = origin & renderObject.size;
      if (bounds.overlaps(selectionRect)) {
        _dragTouchedKeys.add(entry.key);
      }
    }
    for (final key in _dragTouchedKeys) {
      if (!baseSelection.contains(key)) {
        selected.add(key);
      } else {
        selected.remove(key);
      }
    }
    if (!_sameSelection(selected, widget.selectedKeys)) {
      widget.onSelectionChanged(selected);
    }
  }

  void _resetDrag() {
    if (_dragStart == null && _dragCurrent == null && !_dragging) {
      return;
    }
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
      _dragBaseSelection = null;
      _dragTouchedKeys.clear();
      _trackingPrimaryPointer = false;
      _pointerStartedOnTarget = false;
      _dragging = false;
    });
  }

  Offset? _localPositionFor(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return null;
    }
    return renderObject.globalToLocal(globalPosition);
  }

  Rect? get _selectionRect {
    if (_dragStart == null || _dragCurrent == null) {
      return null;
    }
    return Rect.fromPoints(_dragStart!, _dragCurrent!);
  }

  bool _hitsInteractiveRegion(Offset localPosition) {
    return _hitsAnyContext(localPosition, [
      ..._targets.values,
      ..._blankTapBlockers,
    ]);
  }

  bool _hitsAnyContext(Offset localPosition, Iterable<BuildContext> contexts) {
    final regionBox = context.findRenderObject() as RenderBox?;
    if (regionBox == null || !regionBox.attached) {
      return false;
    }
    for (final candidateContext in contexts) {
      final renderObject = candidateContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) {
        continue;
      }
      final origin = renderObject.localToGlobal(
        Offset.zero,
        ancestor: regionBox,
      );
      final bounds = origin & renderObject.size;
      if (bounds.contains(localPosition)) {
        return true;
      }
    }
    return false;
  }

  bool _sameSelection(Set<String> left, Set<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final item in left) {
      if (!right.contains(item)) {
        return false;
      }
    }
    return true;
  }
}

class FileManagerDragSelectionTarget extends StatefulWidget {
  const FileManagerDragSelectionTarget({
    super.key,
    required this.selectionKey,
    required this.enabled,
    required this.child,
  });

  final String selectionKey;
  final bool enabled;
  final Widget child;

  @override
  State<FileManagerDragSelectionTarget> createState() =>
      _FileManagerDragSelectionTargetState();
}

class _FileManagerDragSelectionTargetState
    extends State<FileManagerDragSelectionTarget> {
  _FileManagerDragSelectionState? _selectionState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachToScope();
  }

  @override
  void didUpdateWidget(covariant FileManagerDragSelectionTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionKey != widget.selectionKey ||
        oldWidget.enabled != widget.enabled) {
      _detachFromScope(oldWidget.selectionKey);
      _attachToScope();
    }
  }

  @override
  void dispose() {
    _detachFromScope(widget.selectionKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _attachToScope() {
    final next = _DragSelectionScope.of(context);
    if (_selectionState == next) {
      if (widget.enabled) {
        _selectionState?.registerTarget(widget.selectionKey, context);
      }
      return;
    }
    _detachFromScope(widget.selectionKey);
    _selectionState = next;
    if (widget.enabled) {
      _selectionState?.registerTarget(widget.selectionKey, context);
    }
  }

  void _detachFromScope(String selectionKey) {
    _selectionState?.unregisterTarget(selectionKey, context);
    _selectionState = null;
  }
}

class FileManagerBlankTapRegion extends StatefulWidget {
  const FileManagerBlankTapRegion({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<FileManagerBlankTapRegion> createState() =>
      _FileManagerBlankTapRegionState();
}

class _FileManagerBlankTapRegionState extends State<FileManagerBlankTapRegion> {
  _FileManagerDragSelectionState? _selectionState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachToScope();
  }

  @override
  void didUpdateWidget(covariant FileManagerBlankTapRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _detachFromScope();
      _attachToScope();
    }
  }

  @override
  void dispose() {
    _detachFromScope();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _attachToScope() {
    final next = _DragSelectionScope.of(context);
    if (_selectionState == next) {
      if (widget.enabled) {
        _selectionState?.registerBlankTapBlocker(context);
      }
      return;
    }
    _detachFromScope();
    _selectionState = next;
    if (widget.enabled) {
      _selectionState?.registerBlankTapBlocker(context);
    }
  }

  void _detachFromScope() {
    _selectionState?.unregisterBlankTapBlocker(context);
    _selectionState = null;
  }
}

class _DragSelectionScope extends InheritedWidget {
  const _DragSelectionScope({required this.state, required super.child});

  final _FileManagerDragSelectionState state;

  static _FileManagerDragSelectionState? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DragSelectionScope>()
        ?.state;
  }

  @override
  bool updateShouldNotify(covariant _DragSelectionScope oldWidget) =>
      oldWidget.state != state;
}

class _SelectionRectPainter extends CustomPainter {
  const _SelectionRectPainter({required this.rect});

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final normalized = Rect.fromLTRB(
      rect.left.clamp(0, size.width),
      rect.top.clamp(0, size.height),
      rect.right.clamp(0, size.width),
      rect.bottom.clamp(0, size.height),
    );
    final fill = Paint()..color = const Color(0x332B7FFF);
    final stroke = Paint()
      ..color = const Color(0xFF2B7FFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(normalized, fill);
    canvas.drawRect(normalized, stroke);
  }

  @override
  bool shouldRepaint(covariant _SelectionRectPainter oldDelegate) =>
      oldDelegate.rect != rect;
}
