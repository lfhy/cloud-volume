// 文件管理面包屑：负责显示首页、桶和目录层级，并提供对应跳转入口。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:remote_storage/services/app_modal.dart';

class FileManagerBreadcrumbBar extends StatelessWidget {
  const FileManagerBreadcrumbBar({
    super.key,
    required this.theme,
    required this.activeBucket,
    required this.breadcrumbs,
    required this.onOpenBucketList,
    required this.onOpenBucketRoot,
    required this.onOpenCrumb,
  });

  final ShadThemeData theme;
  final String? activeBucket;
  final List<String> breadcrumbs;
  final VoidCallback onOpenBucketList;
  final VoidCallback onOpenBucketRoot;
  final ValueChanged<int> onOpenCrumb;

  @override
  Widget build(BuildContext context) {
    if (activeBucket == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '文件管理',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '浏览和管理远程存储中的文件。',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),
        ],
      );
    }
    final entries = _entries();
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelStyle = DefaultTextStyle.of(context).style.merge(
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        );
        final layout = _resolveLayout(
          constraints.maxWidth,
          entries,
          labelStyle,
          Directionality.of(context),
          MediaQuery.textScalerOf(context),
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                GestureDetector(
                  onTap: onOpenBucketList,
                  child: Icon(
                    LucideIcons.house,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (layout.hiddenCrumbs.isNotEmpty) ...[
                  _crumbChevron(theme),
                  _hiddenCrumbMenu(context, layout.hiddenCrumbs),
                ],
                for (int i = 0; i < layout.visibleCrumbs.length; i++) ...[
                  _crumbChevron(theme),
                  if (i == layout.visibleCrumbs.length - 1)
                    Expanded(child: _buildCrumb(layout.visibleCrumbs[i], true))
                  else
                    SizedBox(
                      width: _labelWidth(
                        layout.visibleCrumbs[i].label,
                        labelStyle,
                        Directionality.of(context),
                        MediaQuery.textScalerOf(context),
                      ),
                      child: _buildCrumb(layout.visibleCrumbs[i], false),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<_CrumbEntry> _entries() {
    if (activeBucket == null) return const [];
    return [
      _CrumbEntry(index: -1, label: activeBucket!),
      for (int i = 0; i < breadcrumbs.length; i++)
        _CrumbEntry(index: i, label: breadcrumbs[i]),
    ];
  }

  _BreadcrumbLayout _resolveLayout(
    double maxWidth,
    List<_CrumbEntry> entries,
    TextStyle labelStyle,
    TextDirection textDirection,
    TextScaler textScaler,
  ) {
    if (entries.isEmpty || !maxWidth.isFinite) {
      return _BreadcrumbLayout(hiddenCrumbs: const [], visibleCrumbs: entries);
    }
    if (_estimatedWidth(
          entries,
          false,
          labelStyle,
          textDirection,
          textScaler,
        ) <=
        maxWidth) {
      return _BreadcrumbLayout(hiddenCrumbs: const [], visibleCrumbs: entries);
    }
    for (int hiddenCount = 1; hiddenCount < entries.length; hiddenCount++) {
      final visible = entries.sublist(hiddenCount);
      if (_estimatedWidth(
            visible,
            hiddenCount > 0,
            labelStyle,
            textDirection,
            textScaler,
          ) <=
          maxWidth) {
        return _BreadcrumbLayout(
          hiddenCrumbs: entries.sublist(0, hiddenCount),
          visibleCrumbs: visible,
        );
      }
    }
    return _BreadcrumbLayout(
      hiddenCrumbs: entries.sublist(0, entries.length - 1),
      visibleCrumbs: entries.sublist(entries.length - 1),
    );
  }

  double _estimatedWidth(
    List<_CrumbEntry> visible,
    bool hasHiddenCrumbs,
    TextStyle labelStyle,
    TextDirection textDirection,
    TextScaler textScaler,
  ) {
    const homeWidth = 18.0;
    const chevronWidth = 22.0;
    const hiddenWidth = 40.0;
    var total = homeWidth;
    if (hasHiddenCrumbs) {
      total += chevronWidth + hiddenWidth;
    }
    for (final crumb in visible) {
      total +=
          chevronWidth +
          _labelWidth(crumb.label, labelStyle, textDirection, textScaler);
    }
    return total;
  }

  double _labelWidth(
    String label,
    TextStyle labelStyle,
    TextDirection textDirection,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    return painter.width.clamp(28.0, double.infinity);
  }

  Widget _buildCrumb(_CrumbEntry crumb, bool isCurrent) {
    return _crumbLabel(
      crumb.label,
      onTap: () {
        if (crumb.index < 0) {
          onOpenBucketRoot();
          return;
        }
        onOpenCrumb(crumb.index);
      },
      color: isCurrent
          ? theme.colorScheme.foreground
          : theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
  }

  Widget _hiddenCrumbMenu(
    BuildContext context,
    List<_CrumbEntry> hiddenCrumbs,
  ) {
    return ShadButton.ghost(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      onPressed: () => _showHiddenCrumbDialog(context, hiddenCrumbs),
      child: Text(
        '...',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }

  void _showHiddenCrumbDialog(
    BuildContext context,
    List<_CrumbEntry> hiddenCrumbs,
  ) {
    showAppModal<void>(
      context: context,
      builder: (dialogContext) => AppShadDialog(
        title: const Text('跳转到层级'),
        description: const Text('选择要展开的中间路径层级。'),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              for (final crumb in hiddenCrumbs) ...[
                ShadButton.ghost(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    if (crumb.index == -1) {
                      onOpenBucketRoot();
                      return;
                    }
                    onOpenCrumb(crumb.index);
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(crumb.label, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _crumbLabel(
    String label, {
    required VoidCallback onTap,
    required Color color,
    required FontWeight fontWeight,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, fontWeight: fontWeight, color: color),
      ),
    );
  }

  Widget _crumbChevron(ShadThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        LucideIcons.chevronRight,
        size: 14,
        color: theme.colorScheme.mutedForeground,
      ),
    );
  }
}

class _CrumbEntry {
  const _CrumbEntry({required this.index, required this.label});

  final int index;
  final String label;
}

class _BreadcrumbLayout {
  const _BreadcrumbLayout({
    required this.hiddenCrumbs,
    required this.visibleCrumbs,
  });

  final List<_CrumbEntry> hiddenCrumbs;
  final List<_CrumbEntry> visibleCrumbs;
}
