// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

const Duration _bucketQuotaCacheTtl = Duration(minutes: 5);
const Duration _bucketQuotaRequestTimeout = Duration(seconds: 10);

// Quota resolution now happens during _loadBuckets so a single setState renders
// the final list. The post-frame refresh was removed because replacing _buckets
// a second time rebuilt FileListTile subtrees and broke hover state.
extension _FileManagerPageQuota on _FileManagerPageState {
  List<FileManagerBucketEntry> _applyCachedBucketQuotas(
    List<FileManagerBucketEntry> entries,
  ) {
    return entries
        .map((entry) {
          final cached = _matchingQuotaCache(entry);
          return cached == null ? entry : entry.withBucketInfo(cached.bucket);
        })
        .toList(growable: false);
  }

  /// Resolves remote quotas for [entries] and folds them into the returned list
  /// without triggering a setState. Called from _loadBuckets before the single
  /// setState that renders the bucket rows, so hover state is never disrupted.
  Future<List<FileManagerBucketEntry>> _populateBucketQuotas(
    List<FileManagerBucketEntry> entries,
    int generation, {
    required int listingViewGeneration,
    required _MobileFileManagerRequest? mobileRequest,
  }) async {
    bool isCurrentRequest() =>
        mounted &&
        generation == _bucketQuotaRefreshGeneration &&
        _isCurrentListingViewRequest(listingViewGeneration) &&
        _isCurrentMobileFileManagerRequest(mobileRequest);
    final now = DateTime.now();
    final candidates = entries
        .where((entry) => !_hasFreshQuotaCache(entry, now))
        .toList(growable: false);
    if (candidates.isEmpty) return entries;

    final results = await Future.wait<MapEntry<String, BucketInfo>?>(
      candidates.map((entry) async {
        try {
          final quota = await widget.api
              .getBucketQuota(entry.config, entry.bucket.name)
              .timeout(_bucketQuotaRequestTimeout);
          if (!isCurrentRequest()) return null;
          _bucketQuotaCache[entry.id] = _BucketQuotaCacheValue(
            bucket: quota,
            configSignature: _quotaConfigSignature(entry),
            fetchedAt: DateTime.now(),
          );
          return MapEntry(entry.id, quota);
        } catch (error) {
          // Bridge setup failures happen before Go can log, so record them here.
          unawaited(
            AppLog.error(
              'quota refresh failed profile=${entry.profileName} '
              'bucket=${entry.bucket.name} error=$error',
              tag: 'quota',
            ),
          );
          return null;
        }
      }),
    );
    // A newer file view may have superseded this one; do not let its quota
    // cache values outlive the listing that requested them.
    if (!isCurrentRequest()) return entries;

    final updates = Map<String, BucketInfo>.fromEntries(
      results.whereType<MapEntry<String, BucketInfo>>(),
    );
    if (updates.isEmpty) return entries;

    return entries
        .map(
          (entry) => updates[entry.id] == null
              ? entry
              : entry.withBucketInfo(updates[entry.id]!),
        )
        .toList(growable: false);
  }

  _BucketQuotaCacheValue? _matchingQuotaCache(FileManagerBucketEntry entry) {
    final cached = _bucketQuotaCache[entry.id];
    if (cached == null) return null;
    if (cached.configSignature == _quotaConfigSignature(entry)) return cached;
    _bucketQuotaCache.remove(entry.id);
    return null;
  }

  bool _hasFreshQuotaCache(FileManagerBucketEntry entry, DateTime now) {
    final cached = _matchingQuotaCache(entry);
    return cached != null &&
        now.difference(cached.fetchedAt) < _bucketQuotaCacheTtl;
  }

  int _quotaConfigSignature(FileManagerBucketEntry entry) {
    final config = entry.config;
    return Object.hashAll(<Object?>[
      config.storageType,
      config.endpoint,
      config.accessKeyId,
      config.secretAccessKey,
      config.webdavUsername,
      config.webdavPassword,
      config.rootPrefix,
    ]);
  }
}

class _BucketQuotaCacheValue {
  const _BucketQuotaCacheValue({
    required this.bucket,
    required this.configSignature,
    required this.fetchedAt,
  });

  final BucketInfo bucket;
  final int configSignature;
  final DateTime fetchedAt;
}
