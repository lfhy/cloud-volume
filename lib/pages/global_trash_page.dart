// 全局回收站页：默认选中第一个有数据的桶，并以分页方式增量加载该桶的回收站内容。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
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
  const GlobalTrashPage({super.key, required this.api, required this.config});

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;

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
  List<String> _bucketOptions = const <String>[];
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
    if (oldWidget.config != widget.config) {
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
      _bucketOptions = const <String>[];
      _activeBucket = null;
      _nextToken = '';
      _hasMore = false;
    });
    try {
      final buckets = await widget.api.listBuckets(widget.config);
      final bucketNames = buckets
          .map((bucket) => bucket.name)
          .where(widget.config.bucketTrashEnabled)
          .toList(growable: false);
      if (!mounted) {
        return;
      }
      if (bucketNames.isEmpty) {
        setState(() {
          _bucketOptions = const <String>[];
          _loading = false;
        });
        return;
      }

      final preferred =
          previousBucket != null && bucketNames.contains(previousBucket)
          ? previousBucket
          : null;
      final resolved = preferred != null
          ? await _loadBucketFirstPage(preferred)
          : await _findFirstBucketWithEntries(bucketNames);
      if (!mounted) {
        return;
      }
      setState(() {
        _bucketOptions = bucketNames;
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
    final page = await widget.api.listTrashPage(
      widget.config,
      bucket,
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
      final page = await widget.api.listTrashPage(
        widget.config,
        bucket,
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
        widget.config,
        entry.bucket,
        entry.item.id,
      );
      ObjectListingNotifier.instance.markRestored(entry.bucket, [entry.item]);
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
        widget.config,
        entry.bucket,
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
          widget.config,
          entry.bucket,
          entry.item.id,
        );
      }
      if (targets.isNotEmpty) {
        ObjectListingNotifier.instance.markRestored(
          targets.first.bucket,
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
          widget.config,
          entry.bucket,
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
    final confirmed = await showClearTrashDialog(context, bucket);
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
      await widget.api.clearTrash(widget.config, bucket);
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
