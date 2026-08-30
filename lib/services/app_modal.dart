// Unified in-app modal API and platform-aware Shad dialog surface.
// Business dialogs enter here so routing, Android fullscreen presentation,
// system chrome, and desktop sizing stay consistent.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Default max width for standard form / confirm modals.
const double kAppModalDefaultMaxWidth = 480;

/// Default content width used inside many existing dialogs.
const double kAppModalDefaultContentWidth = 420;

// Shad paints its focused secondary border 4px outside input bounds. Keep a
// small in-viewport gutter so scroll clipping never cuts that focus ring.
const EdgeInsets _androidModalScrollPadding = EdgeInsets.all(6);

/// Whether app-modal surfaces should use Android's fullscreen presentation.
bool get usesFullscreenAppModal =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Whether Android has too little post-keyboard height for pinned dialog chrome.
bool usesCompactFullscreenAppModal(BuildContext context) {
  if (!usesFullscreenAppModal) return false;
  final availableHeight =
      MediaQuery.sizeOf(context).height -
      MediaQuery.viewInsetsOf(context).vertical;
  return availableHeight < 480;
}

/// A [ShadDialog] whose surface fills the available Android viewport.
///
/// Desktop and web retain every caller-supplied Shad property. On Android the
/// surface itself extends behind system bars while Shad's inner [SafeArea]
/// keeps title, content, actions, and the close button reachable.
class AppShadDialog extends ShadDialog {
  const AppShadDialog({
    super.key,
    super.title,
    super.description,
    super.child,
    super.actions,
    super.closeIcon,
    super.closeIconData,
    super.closeIconPosition,
    super.radius,
    super.backgroundColor,
    super.expandActionsWhenTiny,
    super.padding,
    super.gap,
    super.constraints,
    super.border,
    super.shadows,
    super.removeBorderRadiusWhenTiny,
    super.actionsAxis,
    super.actionsMainAxisSize,
    super.actionsMainAxisAlignment,
    super.actionsVerticalDirection,
    super.titleStyle,
    super.descriptionStyle,
    super.titleTextAlign,
    super.descriptionTextAlign,
    super.alignment,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.scrollable,
    super.scrollPadding,
    super.actionsGap,
    super.useSafeArea,
    super.titlePinned,
    super.descriptionPinned,
    super.actionsPinned,
  });

  const AppShadDialog.alert({
    super.key,
    super.title,
    super.description,
    super.child,
    super.actions,
    super.closeIcon,
    super.closeIconData,
    super.closeIconPosition,
    super.radius,
    super.backgroundColor,
    super.expandActionsWhenTiny,
    super.padding,
    super.gap,
    super.constraints,
    super.border,
    super.shadows,
    super.removeBorderRadiusWhenTiny,
    super.actionsAxis,
    super.actionsMainAxisSize,
    super.actionsMainAxisAlignment,
    super.actionsVerticalDirection,
    super.titleStyle,
    super.descriptionStyle,
    super.titleTextAlign,
    super.descriptionTextAlign,
    super.alignment,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.scrollable,
    super.scrollPadding,
    super.actionsGap,
    super.useSafeArea,
    super.titlePinned,
    super.descriptionPinned,
    super.actionsPinned,
  }) : super.alert();

  @override
  Widget build(BuildContext context) {
    if (!usesFullscreenAppModal) return super.build(context);
    final compactHeight = usesCompactFullscreenAppModal(context);

    return ShadDialog.raw(
      variant: variant,
      title: title,
      description: description,
      actions: actions,
      closeIcon: closeIcon,
      closeIconData: closeIconData,
      closeIconPosition: closeIconPosition,
      radius: BorderRadius.zero,
      backgroundColor: backgroundColor,
      expandActionsWhenTiny: expandActionsWhenTiny,
      padding: compactHeight
          ? const EdgeInsets.symmetric(horizontal: 24, vertical: 8)
          : padding,
      gap: gap,
      constraints: const BoxConstraints.expand(),
      border: const Border(),
      shadows: const <BoxShadow>[],
      removeBorderRadiusWhenTiny: true,
      actionsAxis: actionsAxis,
      actionsMainAxisSize: actionsMainAxisSize,
      actionsMainAxisAlignment: actionsMainAxisAlignment,
      actionsVerticalDirection: actionsVerticalDirection,
      titleStyle: titleStyle,
      descriptionStyle: descriptionStyle,
      titleTextAlign: titleTextAlign,
      descriptionTextAlign: descriptionTextAlign,
      alignment: alignment,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      scrollable: scrollable,
      scrollPadding: scrollPadding ?? _androidModalScrollPadding,
      actionsGap: actionsGap,
      useSafeArea: true,
      titlePinned: titlePinned,
      descriptionPinned: descriptionPinned,
      actionsPinned: actionsPinned,
      child: child,
    );
  }
}

/// Presents an in-app modal route. Prefer this over bare [showShadDialog].
///
/// The builder should return an [AppShadDialog] (or a widget that builds one)
/// so Android presentation remains fullscreen without changing desktop sizes.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = const Color(0xcc000000),
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  final fullscreen = usesFullscreenAppModal;
  return showShadDialog<T>(
    context: context,
    builder: (dialogContext) {
      final dialog = builder(dialogContext);
      if (!fullscreen) return dialog;

      final theme = ShadTheme.of(dialogContext);
      final iconBrightness = theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: iconBrightness,
          statusBarBrightness: theme.brightness,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: iconBrightness,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: false,
        ),
        child: dialog,
      );
    },
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    animateIn: fullscreen ? const [FadeEffect()] : null,
    animateOut: fullscreen ? const [FadeEffect(begin: 1, end: 0)] : null,
  );
}

/// Convenience builder for title / description / body / trailing action row.
Future<T?> showAppModalDialog<T>({
  required BuildContext context,
  Widget? title,
  Widget? description,
  Widget? child,
  List<Widget> actions = const [],
  double maxWidth = kAppModalDefaultMaxWidth,
  double? contentWidth,
  bool scrollable = false,
  bool barrierDismissible = true,
  bool alert = false,
  bool expandActionsWhenTiny = true,
}) {
  final effectiveContentWidth =
      contentWidth ??
      (maxWidth > 40 ? maxWidth - 40 : maxWidth).clamp(280.0, maxWidth);

  return showAppModal<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      Widget? body = child;
      if (actions.isNotEmpty) {
        body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?child,
            if (child != null) const SizedBox(height: 18),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 10,
              overflowSpacing: 10,
              children: actions,
            ),
          ],
        );
      }

      final sizedBody = body == null
          ? null
          : SizedBox(width: effectiveContentWidth, child: body);
      final constraints = BoxConstraints(maxWidth: maxWidth);
      final effectiveScrollable = usesFullscreenAppModal || scrollable;
      if (alert) {
        return AppShadDialog.alert(
          title: title,
          description: description,
          constraints: constraints,
          scrollable: effectiveScrollable,
          expandActionsWhenTiny: expandActionsWhenTiny,
          child: sizedBody,
        );
      }
      return AppShadDialog(
        title: title,
        description: description,
        constraints: constraints,
        scrollable: effectiveScrollable,
        expandActionsWhenTiny: expandActionsWhenTiny,
        child: sizedBody,
      );
    },
  );
}

/// Yes/no confirmation modal with cancel + confirm actions.
Future<bool?> showAppConfirmModal({
  required BuildContext context,
  required Widget title,
  Widget? description,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool destructive = false,
  double maxWidth = 380,
  bool barrierDismissible = true,
}) {
  return showAppModalDialog<bool>(
    context: context,
    title: title,
    description: description,
    maxWidth: maxWidth,
    barrierDismissible: barrierDismissible,
    actions: [
      Builder(
        builder: (dialogContext) => ShadButton.outline(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
      ),
      Builder(
        builder: (dialogContext) {
          if (destructive) {
            return ShadButton.destructive(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            );
          }
          return ShadButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          );
        },
      ),
    ],
  );
}
