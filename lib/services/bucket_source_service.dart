// Bucket source aggregation.
//
// Centralizes the "list buckets for every account, apply per-account
// bucket-visibility allowlist, respect saved bucket order" pipeline that the
// file-manager home view, the global trash page, and other surfaces need.
// Before this service existed, file_manager_page_sources.dart owned the only
// copy and the global trash page re-implemented a single-account subset,
// which is why the trash page could not see buckets from other accounts.
//
// The service is stateless: every call re-reads profiles from the gateway so
// freshly added / deleted accounts are picked up immediately. Callers that
// need caching (the file manager's quota cache) layer that on top.

import 'dart:async';

import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

/// A single account's resolved config plus the labels the UI shows alongside
/// its buckets. Mirrors the old private `_BucketSourceConfig`.
class BucketSource {
  const BucketSource({
    required this.profileName,
    required this.sourceLabel,
    required this.config,
  });

  final String profileName;
  final String sourceLabel;
  final RemoteStorageConfig config;
}

/// Thrown when a single account fails to load or list buckets. Carries the
/// profile name so callers can offer "edit this account's credentials".
class BucketSourceLoadException implements Exception {
  const BucketSourceLoadException(this.profileName, this.cause);

  final String profileName;
  final Object cause;

  @override
  String toString() => cause.toString();
}

/// A profile failure is isolated so one expired account does not hide buckets
/// belonging to the user's other configured accounts.
class BucketSourceLoadFailure {
  const BucketSourceLoadFailure({
    required this.profileName,
    required this.cause,
  });

  final String profileName;
  final Object cause;
}

/// Aggregation output retains usable buckets alongside isolated failures.
class BucketSourceLoadResult {
  const BucketSourceLoadResult({required this.entries, required this.failures});

  final List<FileManagerBucketEntry> entries;
  final List<BucketSourceLoadFailure> failures;
}

/// Aggregates buckets across all configured accounts.
class BucketSourceService {
  BucketSourceService._();

  static final BucketSourceService instance = BucketSourceService._();

  /// Resolves the [RemoteStorageConfig] for every profile in [profiles].
  ///
  /// When [profiles] is empty the active [fallbackConfig] is used as the only
  /// source, matching the pre-existing file-manager behaviour.
  Future<List<BucketSource>> loadSources(
    RemoteStorageGateway api,
    List<ProfileInfo> profiles, {
    required RemoteStorageConfig fallbackConfig,
  }) async {
    if (profiles.isEmpty) {
      return <BucketSource>[
        BucketSource(
          profileName: 'default',
          sourceLabel: _sourceLabelForConfig(fallbackConfig),
          config: fallbackConfig,
        ),
      ];
    }
    // Disabled accounts are skipped entirely: they must not connect to their
    // backend or appear as load failures. They remain visible in the account
    // management page so the user can re-enable them.
    final activeProfiles = profiles.where((p) => !p.disabled).toList();
    return Future.wait(
      activeProfiles.map((profile) async {
        try {
          final config = await api.loadProfile(profile.name);
          return BucketSource(
            profileName: profile.name,
            sourceLabel: _sourceLabelForConfig(config),
            config: config,
          );
        } catch (error, stackTrace) {
          Error.throwWithStackTrace(
            BucketSourceLoadException(profile.name, error),
            stackTrace,
          );
        }
      }),
    );
  }

  /// Lists buckets for every source, applies per-account bucket-visibility
  /// allowlist, and returns ordered [FileManagerBucketEntry]s.
  ///
  /// The returned order follows the saved bucket order when present
  /// (`api.listBucketOrder`); otherwise accounts appear in profile order and
  /// buckets within an account are sorted by label.
  Future<List<FileManagerBucketEntry>> loadEntries(
    RemoteStorageGateway api,
    List<ProfileInfo> profiles, {
    required RemoteStorageConfig fallbackConfig,
    bool force = false,
  }) async {
    return (await loadEntriesWithFailures(
      api,
      profiles,
      fallbackConfig: fallbackConfig,
      force: force,
    )).entries;
  }

  /// Loads every account independently, preserving usable buckets when a
  /// separate profile has expired credentials or a temporary network error.
  ///
  /// Accounts are loaded and listed **concurrently** with per-account failure
  /// isolation: one slow or unreachable upstream cannot block the others, and a
  /// failing account surfaces as a "reconfigure" action instead of an empty
  /// page. A per-call timeout bounds how long any single upstream is allowed to
  /// stall the aggregate result.
  Future<BucketSourceLoadResult> loadEntriesWithFailures(
    RemoteStorageGateway api,
    List<ProfileInfo> profiles, {
    required RemoteStorageConfig fallbackConfig,
    bool force = false,
  }) async {
    final sources = <BucketSource>[];
    final failures = <BucketSourceLoadFailure>[];
    // Skip disabled accounts before any backend call: they must not connect,
    // appear in the bucket list, or surface as a load failure.
    final profilesToLoad = profiles
        .where((profile) => !profile.disabled)
        .toList(growable: false);
    // Fallback is for the legacy no-profile configuration only. A non-empty
    // profile list whose accounts are all disabled must perform zero backend
    // calls rather than silently reconnecting through fallbackConfig.
    if (profiles.isEmpty) {
      sources.add(
        BucketSource(
          profileName: 'default',
          sourceLabel: _sourceLabelForConfig(fallbackConfig),
          config: fallbackConfig,
        ),
      );
    } else {
      // Load all profiles concurrently so one slow bbolt read does not gate the
      // rest. Results are re-collected in profile order so the fallback sort
      // below stays deterministic.
      final loaded = await Future.wait(
        profilesToLoad.map((profile) => _loadSource(api, profile)),
      );
      for (final result in loaded) {
        if (result.source != null) {
          sources.add(result.source!);
        } else {
          failures.add(
            BucketSourceLoadFailure(
              profileName: result.profileName,
              // result.error is only null in the success branch we just handled.
              cause: result.error!,
            ),
          );
        }
      }
    }
    final entries = <FileManagerBucketEntry>[];
    // List buckets for every source concurrently. A single unreachable account
    // is isolated into `failures` and never blocks the healthy accounts.
    final listings = await Future.wait(
      sources.map((source) => _listBucketsForSource(api, source, force)),
    );
    for (final listing in listings) {
      if (listing.buckets != null) {
        final source = listing.source;
        final views = source.config.bucketViews;
        for (final bucket in listing.buckets!) {
          final view = views[bucket.name];
          // Non-empty bucketViews acts as an allowlist: buckets without an entry
          // are hidden. An empty map means "show everything dynamically".
          if (views.isNotEmpty && view == null) continue;
          entries.add(
            FileManagerBucketEntry.fromBucketInfo(
              bucket: bucket,
              profileName: source.profileName,
              sourceLabel: source.sourceLabel,
              config: source.config,
              view: view,
            ),
          );
        }
      } else {
        failures.add(
          BucketSourceLoadFailure(
            profileName: listing.source.profileName,
            // listing.error is only null in the success branch we just handled.
            cause: listing.error!,
          ),
        );
      }
    }

    final order = await api.listBucketOrder();
    if (order.isNotEmpty) {
      return BucketSourceLoadResult(
        entries: _applySavedOrder(entries, order),
        failures: failures,
      );
    }
    entries.sort((left, right) {
      final leftSource = sources.indexWhere(
        (source) => source.profileName == left.profileName,
      );
      final rightSource = sources.indexWhere(
        (source) => source.profileName == right.profileName,
      );
      if (leftSource != rightSource) {
        return leftSource.compareTo(rightSource);
      }
      return left.label.compareTo(right.label);
    });
    return BucketSourceLoadResult(entries: entries, failures: failures);
  }

  /// Bounds how long a single account is allowed to stall the aggregate load.
  /// Set slightly above the Go bridge `list_buckets` timeout so the backend's
  /// error (with a useful message) is preferred over a generic Dart timeout.
  static const _perAccountTimeout = Duration(seconds: 40);

  Future<_SourceLoadOutcome> _loadSource(
    RemoteStorageGateway api,
    ProfileInfo profile,
  ) async {
    try {
      final config = await api
          .loadProfile(profile.name)
          .timeout(_perAccountTimeout);
      return _SourceLoadOutcome(
        profileName: profile.name,
        source: BucketSource(
          profileName: profile.name,
          sourceLabel: _sourceLabelForConfig(config),
          config: config,
        ),
      );
    } catch (error) {
      return _SourceLoadOutcome(profileName: profile.name, error: error);
    }
  }

  Future<_BucketListingOutcome> _listBucketsForSource(
    RemoteStorageGateway api,
    BucketSource source,
    bool force,
  ) async {
    try {
      final buckets = await api
          .listBuckets(source.config, force: force)
          .timeout(_perAccountTimeout);
      return _BucketListingOutcome(source: source, buckets: buckets);
    } catch (error) {
      return _BucketListingOutcome(source: source, error: error);
    }
  }

  List<FileManagerBucketEntry> _applySavedOrder(
    List<FileManagerBucketEntry> entries,
    List<String> order,
  ) {
    final byId = {for (final entry in entries) entry.id: entry};
    final ordered = <FileManagerBucketEntry>[];
    final seen = <String>{};
    for (final id in order) {
      final entry = byId[id];
      if (entry == null || !seen.add(id)) continue;
      ordered.add(entry);
    }
    for (final entry in entries) {
      if (seen.add(entry.id)) ordered.add(entry);
    }
    return ordered;
  }

  /// Source column shows just the account display name (no storage type) so
  /// narrow columns are not truncated.
  String _sourceLabelForConfig(RemoteStorageConfig config) {
    final name = config.displayName.trim().isNotEmpty
        ? config.displayName.trim()
        : config.storageType == StorageType.baiduPan
        ? '百度网盘'
        : config.storageType == StorageType.webdav
        ? config.webdavUsername.trim()
        : config.accessKeyId.trim();
    return name.isEmpty ? '账号' : name;
  }
}

/// Outcome of loading one profile's config: either a resolved [BucketSource]
/// or the error that prevented resolution. Carries the profile name so a
/// failure can be attributed for the "reconfigure" action.
class _SourceLoadOutcome {
  const _SourceLoadOutcome({
    required this.profileName,
    this.source,
    this.error,
  });

  final String profileName;
  final BucketSource? source;
  final Object? error;
}

/// Outcome of listing one source's buckets: either the bucket list or the
/// error that prevented it. The source is always present so failures can be
/// attributed to the right account.
class _BucketListingOutcome {
  const _BucketListingOutcome({required this.source, this.buckets, this.error});

  final BucketSource source;
  final List<BucketInfo>? buckets;
  final Object? error;
}
