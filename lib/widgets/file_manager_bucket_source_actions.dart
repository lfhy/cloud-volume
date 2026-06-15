part of 'file_manager_bucket_browser.dart';

// Bucket source/action row keeps the bucket browser table columns compact.
class _BucketSourceAndActions extends StatelessWidget {
  const _BucketSourceAndActions({
    required this.sourceLabel,
    required this.showActionColumn,
    required this.actionColumnWidth,
    required this.sourceColumnWidth,
    required this.child,
  });

  final String sourceLabel;
  final bool showActionColumn;
  final double actionColumnWidth;
  final double sourceColumnWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: sourceColumnWidth,
          child: Text(
            sourceLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.mutedForeground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showActionColumn) ...[
          const SizedBox(width: 16),
          SizedBox(
            width: actionColumnWidth,
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ],
    );
  }
}
