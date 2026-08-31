// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// Android bootstrap refreshes rebind logical locations to fresh bucket entries
// before navigation or mutations may issue another provider request.

extension _FileManagerPageMobileInputRebind on _FileManagerPageState {
  void _scheduleMobileFileManagerInputRebind() {
    _mobileInputRefreshNeedsRebind = true;
    // Cache keys intentionally use the stable bucket ID so navigation can
    // preserve history. A bootstrap refresh may change that ID's endpoint or
    // root prefix, though, so every old page must be dropped before Back can
    // revisit it under the rebound entry.
    _invalidateObjectListingCache();
    final inputGeneration = ++_mobileInputGeneration;
    final rebind = _reloadMobileFileManagerLocationAfterInputRefresh(
      inputGeneration,
    );
    _mobileInputRebind = rebind;
    unawaited(
      rebind.whenComplete(() {
        if (identical(_mobileInputRebind, rebind)) {
          _mobileInputRebind = null;
        }
      }),
    );
  }

  /// Waits for the newest inputs, including a retry after a failed refresh.
  /// A false result keeps Android Back on the file page instead of falling
  /// through to the bottom-navigation history with an unsafe old source.
  Future<bool> _ensureMobileFileManagerInputRebound() async {
    while (mounted) {
      final rebind = _mobileInputRebind;
      if (rebind == null) {
        return !_mobileInputRefreshNeedsRebind;
      }
      final inputGeneration = _mobileInputGeneration;
      await rebind;
      if (!mounted) return false;
      // A newer bootstrap update replaced the awaited rebind while it ran.
      if (inputGeneration != _mobileInputGeneration) continue;
      return !_mobileInputRefreshNeedsRebind;
    }
    return false;
  }

  /// Re-resolves every Android location after inputs change without treating a
  /// fresh bootstrap object as a request to abandon the file Back stack.
  Future<void> _reloadMobileFileManagerLocationAfterInputRefresh(
    int inputGeneration,
  ) async {
    final originalLocation = _mobileLocation;
    final originalHistory = List<_MobileFileManagerLocation>.of(
      _mobileLocationHistory,
    );
    final refreshEpoch = ++_mobileNavigationEpoch;
    final request = _MobileFileManagerRequest(
      location: originalLocation,
      epoch: refreshEpoch,
      inputGeneration: inputGeneration,
    );
    final listingViewGeneration = _beginListingViewRequest();
    _beginLoading(message: '正在更新存储信息...');
    try {
      final sourceResult = await _loadBucketEntries(force: true);
      if (!mounted ||
          !_isCurrentListingViewRequest(listingViewGeneration) ||
          !request.isCurrent(this)) {
        return;
      }
      final entries = _applyCachedBucketQuotas(sourceResult.entries);
      final rebound = _rebindMobileFileManagerLocations(
        current: originalLocation,
        history: originalHistory,
        entries: entries,
      );
      setState(() {
        _unavailableBucketSources = sourceResult.failures;
        _buckets = entries;
        _mobileInputRefreshNeedsRebind = false;
        _mobileLocationHistory
          ..clear()
          ..addAll(rebound.history);
        _mobileLocation = rebound.current;
      });
      if (!mounted || inputGeneration != _mobileInputGeneration) return;
      await _loadMobileFileManagerLocation(
        rebound.current,
        forceRefresh: true,
        inputGeneration: inputGeneration,
      );
    } catch (error) {
      if (!mounted ||
          !_isCurrentListingViewRequest(listingViewGeneration) ||
          !request.isCurrent(this)) {
        return;
      }
      setState(() {
        // Leave the gate closed: retry must rebind the current inputs before
        // any Back, refresh, or action-sheet command may use a source again.
        _mobileInputRefreshNeedsRebind = true;
        _error = describeBridgeError(error);
        _endLoading();
      });
    }
  }

  _ReboundMobileFileManagerLocations _rebindMobileFileManagerLocations({
    required _MobileFileManagerLocation current,
    required List<_MobileFileManagerLocation> history,
    required List<FileManagerBucketEntry> entries,
  }) {
    final bucketsById = <String, FileManagerBucketEntry>{
      for (final entry in entries) entry.id: entry,
    };
    final reboundCurrent = _rebindMobileFileManagerLocation(
      current,
      bucketsById,
    );
    if (reboundCurrent != null) {
      return _ReboundMobileFileManagerLocations(
        current: reboundCurrent,
        history: history
            .map(
              (location) =>
                  _rebindMobileFileManagerLocation(location, bucketsById),
            )
            .whereType<_MobileFileManagerLocation>()
            .toList(growable: false),
      );
    }

    // If the active bucket was removed or disabled, return to the newest
    // surviving ancestor instead of retaining a stale config in the Back path.
    for (var index = history.length - 1; index >= 0; index--) {
      final ancestor = _rebindMobileFileManagerLocation(
        history[index],
        bucketsById,
      );
      if (ancestor == null) continue;
      return _ReboundMobileFileManagerLocations(
        current: ancestor,
        history: history
            .take(index)
            .map(
              (location) =>
                  _rebindMobileFileManagerLocation(location, bucketsById),
            )
            .whereType<_MobileFileManagerLocation>()
            .toList(growable: false),
      );
    }
    return const _ReboundMobileFileManagerLocations(
      current: _MobileFileManagerLocation.bucketList(),
      history: <_MobileFileManagerLocation>[],
    );
  }

  _MobileFileManagerLocation? _rebindMobileFileManagerLocation(
    _MobileFileManagerLocation location,
    Map<String, FileManagerBucketEntry> bucketsById,
  ) {
    if (location.kind == _MobileFileManagerLocationKind.bucketList) {
      return const _MobileFileManagerLocation.bucketList();
    }
    final bucket = bucketsById[location.bucket?.id];
    if (bucket == null) return null;
    return switch (location.kind) {
      _MobileFileManagerLocationKind.bucketList =>
        const _MobileFileManagerLocation.bucketList(),
      _MobileFileManagerLocationKind.objects =>
        _MobileFileManagerLocation.objects(bucket, location.prefix),
      _MobileFileManagerLocationKind.trash => _MobileFileManagerLocation.trash(
        bucket,
      ),
    };
  }
}
