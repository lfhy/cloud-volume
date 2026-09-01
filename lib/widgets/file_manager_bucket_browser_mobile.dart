part of 'file_manager_bucket_browser.dart';

// Android bucket rows keep touch-first density and the overflow sheet isolated.
extension _FileManagerBucketMobilePresentation on FileManagerBucketBrowser {
  Widget _buildMobileList(BuildContext context) {
    return ListView.builder(
      itemCount: buckets.length,
      itemBuilder: (context, index) {
        final bucket = buckets[index];
        return KeyedSubtree(
          key: ValueKey('mobile-bucket-${bucket.id}'),
          child: _buildMobileBucketListRow(context, bucket, index),
        );
      },
    );
  }

  Widget _buildMobileBucketListRow(
    BuildContext context,
    FileManagerBucketEntry bucket,
    int index,
  ) {
    final theme = ShadTheme.of(context);
    final actions = _buildBucketActions(bucket);
    return FileListTile(
      compact: true,
      leading: WhiteSurFileIcon(
        assetPath: 'assets/icons/whitesur/places/network-server-balanced.svg',
        size: 28,
      ),
      title: bucket.label,
      subtitleLabel: bucket.sourceLabel,
      onTap: () => _handleBucketTap(bucket),
      showDivider: index != buckets.length - 1,
      trailing: _BucketOverflowMenuButton(
        items: const <Widget>[],
        mobile: true,
        mobileActions: actions,
        bucketLabel: bucket.label,
        color: theme.colorScheme.mutedForeground,
        enabled: actions.isNotEmpty,
      ),
    );
  }
}
