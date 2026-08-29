// 全局回收站页：默认选中第一个有数据的桶，并以分页方式增量加载该桶的回收站内容。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/bucket_source_service.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/object_listing_notifier.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/global_trash_browser.dart';
import 'package:remote_storage/widgets/global_trash_controls.dart';
import 'package:remote_storage/widgets/object_action_dialogs.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'global_trash_page_support.dart';
part 'global_trash_page_view.dart';

class GlobalTrashPage extends StatefulWidget {
  const GlobalTrashPage({
    super.key,
    required this.api,
    required this.config,
    required this.profiles,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final List<ProfileInfo> profiles;

  @override
  State<GlobalTrashPage> createState() => _GlobalTrashPageState();
}

class _GlobalTrashPageState extends State<GlobalTrashPage> {
  static const int _pageSize = 80;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _busyEntries = <String>{};
  final Set<String> _selectedIds = <String>{};
  List<GlobalTrashBrowserEntry> _entries = const <GlobalTrashBrowserEntry>[];
  List<GlobalTrashBucketOption> _bucketOptions =
      const <GlobalTrashBucketOption>[];
  String? _activeBucket;
  String _searchText = '';
  String _nextToken = '';
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
    _scrollController.addListener(_maybeLoadMore);
    unawaited(_loadInitialBucket());
  }

  @override
  void didUpdateWidget(covariant GlobalTrashPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config ||
        oldWidget.profiles != widget.profiles) {
      unawaited(_loadInitialBucket());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSelection(GlobalTrashBrowserEntry entry) {
    setState(() {
      if (_selectedIds.contains(entry.id)) {
        _selectedIds.remove(entry.id);
      } else {
        _selectedIds.add(entry.id);
      }
    });
  }

  void _toggleSelectAllFiltered() {
    final selectableIds = _filteredEntries
        .where((entry) => !_busyEntries.contains(entry.id))
        .map((entry) => entry.id)
        .toList(growable: false);
    final allSelected =
        selectableIds.isNotEmpty && selectableIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(selectableIds);
      } else {
        _selectedIds.addAll(selectableIds);
      }
    });
  }

  Future<void> _loadInitialBucket() async {
    final previousBucket = _activeBucket;
    setState(() {
      _loading = true;
      _error = null;
      _entries = const <GlobalTrashBrowserEntry>[];
      _bucketOptions = const <GlobalTrashBucketOption>[];
      _activeBucket = null;
      _activeBucketConfig = null;
      _activeBucketProfile = null;
      _nextToken = '';
      _hasMore = false;
    });
    try {
      // Use the shared aggregation service so the trash page sees the exact
      // same bucket set as the file-manager home (all accounts, same
      // allowlist + ordering). Each entry already carries the account config
      // and effective root prefix to use for trash calls.
      final entries = await BucketSourceService.instance.loadEntries(
        widget.api,
        widget.profiles,
        fallbackConfig: widget.config,
      );
      final trashEntries = entries
          .where((entry) => entry.config.bucketTrashEnabled(entry.bucket.name))
          .toList(growable: false);
      // Remember the lookup so _loadBucketFirstPage / _reloadBucket can find
      // the right account config without re-resolving every page.
      _bucketEntryById
        ..clear()
        ..addAll({for (final entry in trashEntries) entry.id: entry});
      final bucketIds = trashEntries
          .map((entry) => entry.id)
          .toList(growable: false);
      if (!mounted) {
        return;
      }
      if (bucketIds.isEmpty) {
        setState(() {
          _bucketOptions = const <GlobalTrashBucketOption>[];
          _loading = false;
        });
        return;
      }

      final preferred =
          previousBucket != null && bucketIds.contains(previousBucket)
          ? previousBucket
          : null;
      final resolved = preferred != null
          ? await _loadBucketFirstPage(preferred)
          : await _findFirstBucketWithEntries(bucketIds);
      if (!mounted) {
        return;
      }
      setState(() {
        // Build the dropdown options from the resolved entries so the filter
        // shows the same label the file-manager home uses (custom display
        // name when set, real bucket name otherwise).
        _bucketOptions = trashEntries
            .map(
              (entry) =>
                  GlobalTrashBucketOption(id: entry.id, label: entry.label),
            )
            .toList(growable: false);
        _activeBucket = resolved.bucket;
        _entries = resolved.entries;
        _nextToken = resolved.page.nextToken;
        _hasMore = resolved.page.hasMore;
        _selectedIds.removeWhere(
          (id) => !_entries.any((entry) => entry.id == id),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<_BucketTrashLoadResult> _findFirstBucketWithEntries(
    List<String> bucketNames,
  ) async {
    _BucketTrashLoadResult? emptyResult;
    for (final bucket in bucketNames) {
      final result = await _loadBucketFirstPage(bucket);
      if (result.entries.isNotEmpty) {
        return result;
      }
      emptyResult ??= result;
    }
    return emptyResult ?? await _loadBucketFirstPage(bucketNames.first);
  }

  Future<_BucketTrashLoadResult> _loadBucketFirstPage(String bucket) async {
    // bucket here is the FileManagerBucketEntry.id (profileName::bucket).
    // The entry's config already has the effective root prefix merged in, so
    // we can pass it straight to listTrashPage without re-deriving prefixes.
    final entry = _bucketEntryById[bucket];
    final config = entry?.config ?? _activeConfig;
    if (entry != null) {
      _activeBucketConfig = entry.config;
      _activeBucketProfile = entry.profileName;
    }
    final page = await widget.api.listTrashPage(
      config,
      entry?.bucket.name ?? bucket,
      '',
      _pageSize,
    );
    return _BucketTrashLoadResult(
      bucket: bucket,
      page: page,
      entries: page.items
          .map((item) => GlobalTrashBrowserEntry(bucket: bucket, item: item))
          .toList(growable: false),
    );
  }

  final Map<String, FileManagerBucketEntry> _bucketEntryById = {};
  RemoteStorageConfig? _activeBucketConfig;
  // ignore: unused_field
  String? _activeBucketProfile;

  /// Resolves the [RemoteStorageConfig] that should be used for trash calls
  /// on the currently active bucket. Falls back to the active account config
  /// when the bucket has not been resolved yet (e.g. before the first load).
  RemoteStorageConfig get _activeConfig => _activeBucketConfig ?? widget.config;

  /// Resolves the [RemoteStorageConfig] for a trash entry or active-bucket id.
  /// [bucketId] is the FileManagerBucketEntry id (`profileName::bucket`).
  /// Returns the cached active config when the id is unknown (e.g. entries
  /// from a previous load before a profile was renamed).
  RemoteStorageConfig _configForBucketId(String bucketId) {
    return _bucketEntryById[bucketId]?.config ?? _activeConfig;
  }

  /// Returns the real provider bucket name for a trash entry / active-bucket
  /// id. Falls back to the id itself when the entry is no longer cached so
  /// the call still goes through with a best-effort name.
  String _providerBucketName(String bucketId) {
    return _bucketEntryById[bucketId]?.bucket.name ?? bucketId;
  }

  /// Returns the friendly label for the active bucket (custom display name
  /// when configured, otherwise the real bucket name). Used by the clear-
  /// trash confirmation dialog and any UI that shows the current bucket.
  String? get _activeBucketLabel {
    final id = _activeBucket;
    if (id == null) return null;
    return _bucketEntryById[id]?.label ?? _providerBucketName(id);
  }

  Future<void> _switchBucket(String bucket) async {
    if (_activeBucket == bucket || _loading) {
      return;
    }
    await _reloadBucket(bucket, resetScroll: true);
  }

  Future<void> _reloadBucket(String bucket, {required bool resetScroll}) async {
    setState(() {
      _loading = true;
      _error = null;
      _entries = const <GlobalTrashBrowserEntry>[];
      _selectedIds.clear();
      _nextToken = '';
      _hasMore = false;
    });
    try {
      final result = await _loadBucketFirstPage(bucket);
      if (!mounted) {
        return;
      }
      setState(() {
        _activeBucket = bucket;
        _entries = result.entries;
        _nextToken = result.page.nextToken;
        _hasMore = result.page.hasMore;
        _loading = false;
      });
      if (resetScroll && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }
    if (position.pixels < position.maxScrollExtent - 520) {
      return;
    }
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    final bucket = _activeBucket;
    if (bucket == null || _loadingMore || !_hasMore) {
      return;
    }
    _loadingMore = true;
    try {
      final entry = _bucketEntryById[bucket];
      final page = await widget.api.listTrashPage(
        entry?.config ?? _activeConfig,
        entry?.bucket.name ?? bucket,
        _nextToken,
        _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final merged = <GlobalTrashBrowserEntry>[
          ..._entries,
          ...page.items.map(
            (item) => GlobalTrashBrowserEntry(bucket: bucket, item: item),
          ),
        ];
        merged.sort(
          (left, right) => right.item.deletedAt.compareTo(left.item.deletedAt),
        );
        _entries = merged;
        _nextToken = page.nextToken;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) {
        showAppErrorToast(context, message: error.toString());
      }
    } finally {
      _loadingMore = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _showPageSnack(String message) {
    if (!mounted) {
      return;
    }
    showAppToast(context, message: message);
  }

  Future<void> _restoreEntry(GlobalTrashBrowserEntry entry) async {
    await _runBusy(<GlobalTrashBrowserEntry>[entry], () async {
      await widget.api.restoreTrashItem(
        _configForBucketId(entry.bucket),
        _providerBucketName(entry.bucket),
        entry.item.id,
        originalKey: entry.item.originalKey,
        isDirectory: entry.item.isDir,
      );
      ObjectListingNotifier.instance.markRestored(
        _providerBucketName(entry.bucket),
        [entry.item],
      );
      await _reloadBucket(entry.bucket, resetScroll: false);
      _showPageSnack('已恢复 ${entry.item.name}');
    });
  }

  Future<void> _deleteEntry(GlobalTrashBrowserEntry entry) async {
    final confirmed = await showDeleteTrashItemDialog(context, entry.item);
    if (!confirmed) {
      return;
    }
    await _runBusy(<GlobalTrashBrowserEntry>[entry], () async {
      await widget.api.deleteTrashItem(
        _configForBucketId(entry.bucket),
        _providerBucketName(entry.bucket),
        entry.item.id,
      );
      await _reloadBucket(entry.bucket, resetScroll: false);
    });
  }

  Future<void> _restoreSelected() async {
    final targets = _filteredEntries
        .where((entry) => _selectedIds.contains(entry.id))
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }
    await _runBusy(targets, () async {
      for (final entry in targets) {
        await widget.api.restoreTrashItem(
          _configForBucketId(entry.bucket),
          _providerBucketName(entry.bucket),
          entry.item.id,
          originalKey: entry.item.originalKey,
          isDirectory: entry.item.isDir,
        );
      }
      if (targets.isNotEmpty) {
        ObjectListingNotifier.instance.markRestored(
          _providerBucketName(targets.first.bucket),
          targets.map((entry) => entry.item),
        );
      }
      if (_activeBucket != null) {
        await _reloadBucket(_activeBucket!, resetScroll: false);
      }
      _showPageSnack('已恢复 ${targets.length} 个项目');
    });
  }

  Future<void> _deleteSelected() async {
    final targets = _filteredEntries
        .where((entry) => _selectedIds.contains(entry.id))
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }
    final confirmed = await showDeleteTrashItemsDialog(context, targets.length);
    if (!confirmed) {
      return;
    }
    await _runBusy(targets, () async {
      for (final entry in targets) {
        await widget.api.deleteTrashItem(
          _configForBucketId(entry.bucket),
          _providerBucketName(entry.bucket),
          entry.item.id,
        );
      }
      if (_activeBucket != null) {
        await _reloadBucket(_activeBucket!, resetScroll: false);
      }
    });
  }

  Future<void> _clearActiveBucketTrash() async {
    final bucket = _activeBucket;
    if (bucket == null || _entries.isEmpty) {
      return;
    }
    final label = _activeBucketLabel ?? _providerBucketName(bucket);
    final confirmed = await showClearTrashDialog(context, label);
    if (!confirmed) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _busyEntries.clear();
      _selectedIds.clear();
    });
    try {
      await widget.api.clearTrash(
        _configForBucketId(bucket),
        _providerBucketName(bucket),
      );
      if (!mounted) {
        return;
      }
      await _reloadBucket(bucket, resetScroll: false);
      _showPageSnack('已清空 $bucket 的回收站');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _runBusy(
    List<GlobalTrashBrowserEntry> entries,
    Future<void> Function() action,
  ) async {
    setState(() {
      for (final entry in entries) {
        _busyEntries.add(entry.id);
        _selectedIds.remove(entry.id);
      }
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted) {
        setState(() {
          for (final entry in entries) {
            _busyEntries.remove(entry.id);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => buildPage(context);
}
