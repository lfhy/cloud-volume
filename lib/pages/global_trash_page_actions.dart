// ignore_for_file: invalid_use_of_protected_member

part of 'global_trash_page.dart';

// 全局回收站条目/批量 mutation：恢复、彻底删除、清空与 busy 包装。
// 从主页面文件拆出以守住 500 行上限；与加载/翻页逻辑的边界是
// _reloadBucket——mutation 完成后由它刷新当前桶。

extension _GlobalTrashPageActions on _GlobalTrashPageState {
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
}
