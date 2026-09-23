// Shared Android selection-mode chrome (两态选择模型): the morphing top bar
// (取消 / 已选中 N 个 X / 全选) and the bottom contextual action bar that
// replaces both the per-row `…` drawers and the bottom navigation bar while a
// selection is active. Browse state shows a quiet trailing circle per row
// instead (MobileRowSelectDot). Desktop surfaces never use this file.

import 'package:flutter/material.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:remote_storage/widgets/mobile_page_chrome.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Selection-state top bar. It replaces the page header while a selection is
/// active: 取消 exits selection, the centered bold title counts it, and
/// 全选/取消全选 toggles the currently filtered item set.
class MobileSelectionHeader extends StatelessWidget {
  const MobileSelectionHeader({
    super.key,
    required this.count,
    required this.noun,
    required this.allSelected,
    required this.onCancel,
    required this.onToggleSelectAll,
  });

  final int count;

  /// Counted noun shown in the title, e.g. 文件 / 项 / 任务.
  final String noun;
  final bool allSelected;
  final VoidCallback onCancel;
  final VoidCallback onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _headerTextButton(context, label: '取消', onPressed: onCancel),
        Expanded(
          child: Text(
            '已选中 $count 个$noun',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ),
        _headerTextButton(
          context,
          label: allSelected ? '取消全选' : '全选',
          onPressed: onToggleSelectAll,
        ),
      ],
    );
  }

  Widget _headerTextButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
  }) {
    final theme = ShadTheme.of(context);
    return ShadButton.ghost(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Selection-state bottom action bar (百度网盘式): every action is visible —
/// up to four in a single row, otherwise two balanced rows of icon-over-label
/// items; there is no「更多」overflow. Renders nothing when [actions] is empty
/// and shows a spinner row while [busy]. The bar is full-bleed: pages place it
/// outside their horizontal padding and it owns its bottom safe-area inset
/// (the bottom navigation bar is hidden whenever this bar is visible).
class MobileSelectionBottomBar extends StatelessWidget {
  const MobileSelectionBottomBar({
    super.key,
    required this.actions,
    this.busy = false,
  });

  final List<MobilePageAction> actions;
  final bool busy;

  static const int _singleRowLimit = 4;
  static const double _rowHeight = 60;

  @override
  Widget build(BuildContext context) {
    if (!busy && actions.isEmpty) return const SizedBox.shrink();
    final theme = ShadTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.border.withValues(alpha: 0.55),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: busy
            ? const SizedBox(
                height: _rowHeight,
                child: Center(
                  child: AppLoadingIndicator(size: 18, strokeWidth: 2.2),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in _actionRows())
                    SizedBox(
                      height: _rowHeight,
                      child: Row(
                        children: [
                          for (final action in row)
                            Expanded(
                              child: _SelectionBarButton(action: action),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// ≤4 actions stay in one row; more split into two balanced rows (5→3+2,
  /// 6→3+3, 7→4+3) so neither row is left with a lonely trailing item.
  List<List<MobilePageAction>> _actionRows() {
    if (actions.length <= _singleRowLimit) {
      return <List<MobilePageAction>>[actions];
    }
    final firstRowCount = (actions.length + 1) ~/ 2;
    return <List<MobilePageAction>>[
      actions.take(firstRowCount).toList(growable: false),
      actions.skip(firstRowCount).toList(growable: false),
    ];
  }
}

class _SelectionBarButton extends StatelessWidget {
  const _SelectionBarButton({required this.action});

  final MobilePageAction action;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Semantics(
      label: action.label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action.onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, size: 21, color: theme.colorScheme.primary),
            const SizedBox(height: 3),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Browse-state trailing affordance: a quiet outlined circle that enters
/// selection mode for its row. In selection state rows switch to the leading
/// ListSelectionControl instead, so this dot only ever renders unselected.
class MobileRowSelectDot extends StatelessWidget {
  const MobileRowSelectDot({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '选择',
      child: ListSelectionControl(
        selected: false,
        onTap: onTap,
        touchTargetSize: 48,
      ),
    );
  }
}

/// One label-over-value line inside [showMobileDetailSheet].
class MobileDetailRow {
  const MobileDetailRow(this.label, this.value);

  final String label;
  final String value;
}

/// Bottom sheet showing an item's metadata (文件详情): gray small label on
/// top, bold value below — the info the list surface already carries (name,
/// size, timestamps, full path, bucket). Pure information, no actions.
Future<void> showMobileDetailSheet(
  BuildContext context, {
  required String title,
  required List<MobileDetailRow> rows,
}) async {
  await showAppModal<void>(
    context: context,
    builder: (dialogContext) {
      final theme = ShadTheme.of(dialogContext);
      return AppShadDialog(
        title: Text(title),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // No maxLines: full paths are the only full-text surface
                    // here, values must wrap (same contract as task details).
                    Text(
                      row.value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
