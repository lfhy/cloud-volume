// Unified in-app modal API and platform-aware Shad dialog surface.
// Business dialogs enter here so Android bottom sheets, system chrome, and
// desktop sizing stay consistent.

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

// Keep a visible slice of the dimmed page above every Android sheet, including
// editors with an Expanded middle pane. The route still supplies the keyboard
// bound; this only caps the portion a sheet may occupy inside that bound.
const double _androidSheetMaxHeightFraction = .90;

/// Whether app-modal surfaces should use Android's bottom-sheet presentation.
bool get usesAndroidAppModalSheet =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Compatibility alias for callers compiled against the former Android
/// fullscreen presentation name.
@Deprecated('Use usesAndroidAppModalSheet instead')
bool get usesFullscreenAppModal => usesAndroidAppModalSheet;

double _androidSheetMaxHeight(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  final postImeHeight =
      mediaQuery.size.height -
      mediaQuery.viewInsets.vertical -
      mediaQuery.padding.top;
  return postImeHeight > 0 ? postImeHeight * _androidSheetMaxHeightFraction : 0;
}

/// Whether Android has too little post-keyboard height for pinned sheet chrome.
bool usesCompactAndroidAppModalSheet(BuildContext context) {
  if (!usesAndroidAppModalSheet) return false;
  final mediaQuery = MediaQuery.of(context);
  // The sheet deliberately leaves the status-bar band to the scrim and keeps
  // its contents above the navigation area, so compact mode must account for
  // both safe insets as well as the IME.
  final availableHeight =
      _androidSheetMaxHeight(context) - mediaQuery.padding.bottom;
  return availableHeight < 480;
}

/// Compatibility alias for the former fullscreen compact-height helper.
@Deprecated('Use usesCompactAndroidAppModalSheet instead')
bool usesCompactFullscreenAppModal(BuildContext context) =>
    usesCompactAndroidAppModalSheet(context);

/// A [ShadDialog] that becomes a bottom-anchored Android sheet.
///
/// Desktop and web retain every caller-supplied Shad property. Android sheets
/// keep their background attached to the physical bottom edge while Shad's
/// inner [SafeArea] keeps title, content, actions, and the close button out of
/// the system navigation area. Long editors opt into [androidFillHeight].
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
    this.androidFillHeight = false,
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
    this.androidFillHeight = false,
  }) : super.alert();

  /// Lets long Android editors fill the capped post-IME sheet height.
  /// Compact sheets remain scrollable instead of forcing a bounded flex tree.
  final bool androidFillHeight;

  @override
  Widget build(BuildContext context) {
    if (!usesAndroidAppModalSheet) return super.build(context);
    final compactHeight = usesCompactAndroidAppModalSheet(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final maxSheetHeight = _androidSheetMaxHeight(context);
    final sheetConstraints = androidFillHeight && !compactHeight
        ? BoxConstraints(
            minWidth: double.infinity,
            minHeight: maxSheetHeight,
            maxHeight: maxSheetHeight,
          )
        : BoxConstraints(minWidth: double.infinity, maxHeight: maxSheetHeight);

    final sheet = ShadDialog.raw(
      variant: variant,
      title: title,
      description: description,
      actions: actions,
      closeIcon: closeIcon,
      closeIconData: closeIconData,
      closeIconPosition: closeIconPosition,
      radius: const BorderRadius.vertical(top: Radius.circular(20)),
      backgroundColor: backgroundColor,
      expandActionsWhenTiny: expandActionsWhenTiny,
      padding: compactHeight
          ? const EdgeInsets.symmetric(horizontal: 24, vertical: 8)
          : padding,
      gap: gap,
      // A loose cap lets ordinary confirmation/form sheets shrink-wrap.
      // Editors that own an Expanded middle pane explicitly fill this cap.
      constraints: sheetConstraints,
      border: Border(
        top: BorderSide(color: ShadTheme.of(context).colorScheme.border),
      ),
      shadows: shadows,
      // Shad removes radii below its `sm` breakpoint by default. A sheet needs
      // its upper corners on phones, so keep them regardless of width.
      removeBorderRadiusWhenTiny: false,
      actionsAxis: actionsAxis,
      actionsMainAxisSize: actionsMainAxisSize,
      actionsMainAxisAlignment: actionsMainAxisAlignment,
      actionsVerticalDirection: actionsVerticalDirection,
      titleStyle: titleStyle,
      descriptionStyle: descriptionStyle,
      titleTextAlign: titleTextAlign,
      descriptionTextAlign: descriptionTextAlign,
      alignment: Alignment.bottomCenter,
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

    // SafeArea normally also adds the global top inset, which would create a
    // phantom gap above short sheets. Reserve that band outside the surface so
    // it stays dimmed, then remove only its top padding before Shad applies its
    // own SafeArea. Left/right cutouts and the bottom navigation inset remain.
    return Padding(
      padding: EdgeInsets.only(top: safeTop),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: sheet,
      ),
    );
  }
}

/// Presents an in-app modal route. Prefer this over bare [showShadDialog].
///
/// The builder should return an [AppShadDialog] (or a widget that builds one)
/// so Android presentation is a bottom sheet without changing desktop sizes.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = const Color(0xcc000000),
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  final androidSheet = usesAndroidAppModalSheet;
  return showShadDialog<T>(
    context: context,
    builder: (dialogContext) {
      final dialog = builder(dialogContext);
      if (!androidSheet) return dialog;

      final theme = ShadTheme.of(dialogContext);
      final iconBrightness = theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          // The status bar stays over the dimmed backdrop rather than the
          // sheet, whereas the navigation bar sits on the sheet surface.
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
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
    animateIn: androidSheet
        ? const [
            SlideEffect(
              begin: Offset(0, 1),
              end: Offset.zero,
              duration: Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            ),
          ]
        : null,
    animateOut: androidSheet
        ? const [
            SlideEffect(
              begin: Offset.zero,
              end: Offset(0, 1),
              duration: Duration(milliseconds: 220),
              curve: Curves.easeInCubic,
            ),
          ]
        : null,
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
      final effectiveScrollable = usesAndroidAppModalSheet || scrollable;
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
