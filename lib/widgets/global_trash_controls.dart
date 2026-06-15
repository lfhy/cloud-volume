// Global trash controls keep filtering and fixed header actions out of the page file.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String allBucketsFilter = '__all_buckets__';

class GlobalTrashFilters extends StatelessWidget {
  const GlobalTrashFilters({
    super.key,
    required this.searchController,
    required this.bucketFilter,
    required this.bucketOptions,
    required this.onBucketChanged,
  });

  final TextEditingController searchController;
  final String bucketFilter;
  final List<String> bucketOptions;
  final ValueChanged<String?> onBucketChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ShadInput(
            controller: searchController,
            placeholder: const Text('搜索名称或原路径'),
          ),
        ),
        const SizedBox(width: 12),
        _dropdown<String>(
          value: bucketFilter,
          items: bucketOptions,
          labelBuilder: (value) => value == allBucketsFilter ? '全部存储桶' : value,
          onChanged: onBucketChanged,
          width: 170,
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T value) labelBuilder,
    required ValueChanged<T?> onChanged,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: ShadSelect<T>(
        key: ValueKey<Object>(value as Object),
        minWidth: width,
        initialValue: value,
        placeholder: Text(
          value.toString().isEmpty ? '选择存储桶' : labelBuilder(value),
        ),
        selectedOptionBuilder: (context, selected) =>
            Text(labelBuilder(selected), overflow: TextOverflow.ellipsis),
        options: items
            .map(
              (item) => ShadOption<T>(
                value: item,
                child: Text(
                  labelBuilder(item),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
        onChanged: onChanged,
      ),
    );
  }
}

class GlobalTrashHeaderActions extends StatelessWidget {
  const GlobalTrashHeaderActions({
    super.key,
    required this.selectedCount,
    required this.loading,
    required this.onRefresh,
    required this.onRestoreSelected,
    required this.onDeleteSelected,
    required this.onClearTrash,
    required this.onClearSelection,
  });

  final int selectedCount;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onRestoreSelected;
  final VoidCallback onDeleteSelected;
  final VoidCallback? onClearTrash;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final hasSelection = selectedCount > 0;

    if (!hasSelection) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          ShadButton.outline(
            onPressed: loading ? null : onRefresh,
            child: const Text('刷新'),
          ),
          ShadButton.destructive(
            onPressed: loading ? null : onClearTrash,
            child: const Text('清空回收站'),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: hasSelection
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : theme.colorScheme.secondary.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '已选 $selectedCount 项',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: hasSelection
                  ? theme.colorScheme.primary
                  : theme.colorScheme.mutedForeground,
            ),
          ),
        ),
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: hasSelection ? onRestoreSelected : null,
          child: const Text('批量恢复'),
        ),
        ShadButton.destructive(
          size: ShadButtonSize.sm,
          onPressed: hasSelection ? onDeleteSelected : null,
          child: const Text('批量彻底删除'),
        ),
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: hasSelection ? onClearSelection : null,
          child: const Text('清空选择'),
        ),
      ],
    );
  }
}
