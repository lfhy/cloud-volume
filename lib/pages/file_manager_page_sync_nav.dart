part of 'file_manager_page.dart';

// Resolves sync-task opens without letting an old discovery response steal
// a file page after Back, cancellation, or a newer tap.

/// The primary listing that was loading before a desktop sync open began.
enum _DesktopListingResumeKind { bucketList, objects, trash }

class _DesktopListingResumeTarget {
  const _DesktopListingResumeTarget._(
    this.kind, {
    this.bucket,
    this.prefix = '',
  });

  const _DesktopListingResumeTarget.bucketList()
    : this._(_DesktopListingResumeKind.bucketList);

  const _DesktopListingResumeTarget.objects(
    FileManagerBucketEntry bucket,
    String prefix,
  ) : this._(_DesktopListingResumeKind.objects, bucket: bucket, prefix: prefix);

  const _DesktopListingResumeTarget.trash(FileManagerBucketEntry bucket)
    : this._(_DesktopListingResumeKind.trash, bucket: bucket);

  final _DesktopListingResumeKind kind;
  final FileManagerBucketEntry? bucket;
  final String prefix;

  bool matches(_DesktopListingResumeTarget other) =>
      kind == other.kind &&
      bucket?.id == other.bucket?.id &&
      prefix == other.prefix;
}

/// Loading fields that a cancelled desktop sync open must restore.
class _FileManagerLoadingSnapshot {
  const _FileManagerLoadingSnapshot({
    required this.loading,
    required this.message,
    required this.detail,
    required this.error,
    required this.resumeTarget,
  });

  final bool loading;
  final String message;
  final String? detail;
  final String? error;
  final _DesktopListingResumeTarget? resumeTarget;
}

extension _FileManagerPageSyncNav on _FileManagerPageState {
  void _recordDesktopListingResumeTarget(_DesktopListingResumeTarget target) {
    if (!_usesMobileNavigation) {
      _desktopListingResumeTarget = target;
    }
  }

  void schedulePendingSyncRemoteOpen(
    SyncRemoteOpenRequest request,
    int ticket,
  ) {
    final generation = ++_pendingSyncRemoteOpenGeneration;
    if (_usesMobileNavigation) {
      _beginPendingMobileSyncRemoteOpen(request, ticket);
    } else {
      _beginPendingDesktopSyncRemoteOpen(generation);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_applyPendingSyncRemoteOpen(request, ticket, generation));
    });
  }

  void _beginPendingMobileSyncRemoteOpen(
    SyncRemoteOpenRequest request,
    int ticket,
  ) {
    if (_activeMobileSyncRemoteOpen != null &&
        _activeMobileSyncRemoteOpenTicket != ticket) {
      _rollbackPendingMobileSyncRemoteOpenPosition();
    }
    if (_activeMobileSyncRemoteOpen == null) {
      _mobileSyncRemoteOpenOrigin = _mobileLocation;
      _mobileSyncRemoteOpenHistoryBase = _mobileLocationHistory.length;
    }
    _activeMobileSyncRemoteOpen = request;
    _activeMobileSyncRemoteOpenTicket = ticket;
  }

  void _rollbackPendingMobileSyncRemoteOpenPosition() {
    final origin = _mobileSyncRemoteOpenOrigin;
    final historyBase = _mobileSyncRemoteOpenHistoryBase;
    if (origin == null || historyBase == null) return;
    if (historyBase < _mobileLocationHistory.length) {
      _mobileLocationHistory.removeRange(
        historyBase,
        _mobileLocationHistory.length,
      );
    }
    _mobileLocation = origin;
    _mobileNavigationEpoch++;
  }

  void _beginPendingDesktopSyncRemoteOpen(int generation) {
    _beginListingViewRequest();
    if (_activeDesktopSyncRemoteOpenGeneration == null) {
      _desktopSyncLoadingSnapshot = _FileManagerLoadingSnapshot(
        loading: _loading,
        message: _loadingMessage,
        detail: _loadingDetail,
        error: _error,
        resumeTarget: _desktopListingResumeTarget,
      );
    }
    _activeDesktopSyncRemoteOpenGeneration = generation;
  }

  void _cancelPendingDesktopSyncRemoteOpen() {
    final snapshot = _desktopSyncLoadingSnapshot;
    if (_activeDesktopSyncRemoteOpenGeneration == null || snapshot == null) {
      return;
    }
    _pendingSyncRemoteOpenGeneration++;
    _activeDesktopSyncRemoteOpenGeneration = null;
    _desktopSyncLoadingSnapshot = null;
    _restoreDesktopSyncLoadingSnapshot(snapshot);
  }

  void _restoreDesktopSyncLoadingSnapshot(
    _FileManagerLoadingSnapshot snapshot,
  ) {
    _loadingDetailTimer?.cancel();
    _loadingDetailTimer = null;
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _loading = snapshot.loading;
      _loadingMessage = snapshot.message;
      _loadingDetail = snapshot.detail;
      _error = snapshot.error;
      _pagingObjects = false;
      _pagingTrash = false;
    });
    if (snapshot.loading) {
      _resumeDesktopLoadingAfterSyncCancellation(snapshot.resumeTarget);
    }
  }

  void _resumeDesktopLoadingAfterSyncCancellation(
    _DesktopListingResumeTarget? resumeTarget,
  ) {
    if (resumeTarget != null) {
      switch (resumeTarget.kind) {
        case _DesktopListingResumeKind.bucketList:
          unawaited(_loadBuckets(force: true));
          return;
        case _DesktopListingResumeKind.objects:
          unawaited(
            _loadObjects(
              resumeTarget.bucket!,
              resumeTarget.prefix,
              forceRefresh: true,
            ),
          );
          return;
        case _DesktopListingResumeKind.trash:
          unawaited(_openBucketTrash(bucket: resumeTarget.bucket!));
          return;
      }
    }
    // Defensive fallback for loading flows that predate primary-view targets.
    final bucket = _activeBucketEntry;
    if (bucket == null) {
      unawaited(_loadBuckets(force: true));
      return;
    }
    if (_showTrash) {
      unawaited(_openBucketTrash(bucket: bucket));
      return;
    }
    unawaited(_loadObjects(bucket, _prefix, forceRefresh: true));
  }

  void _finishPendingDesktopSyncRemoteOpen(
    int generation, {
    bool restoreSnapshot = false,
  }) {
    if (_activeDesktopSyncRemoteOpenGeneration != generation) return;
    final snapshot = _desktopSyncLoadingSnapshot;
    _activeDesktopSyncRemoteOpenGeneration = null;
    _desktopSyncLoadingSnapshot = null;
    if (restoreSnapshot && snapshot != null) {
      _restoreDesktopSyncLoadingSnapshot(snapshot);
    }
  }

  bool _isCurrentPendingSyncRemoteOpen(
    SyncRemoteOpenRequest request,
    int ticket,
    int generation,
  ) =>
      mounted &&
      generation == _pendingSyncRemoteOpenGeneration &&
      (!_usesMobileNavigation
          ? _activeDesktopSyncRemoteOpenGeneration == generation
          : (identical(_activeMobileSyncRemoteOpen, request) &&
                _activeMobileSyncRemoteOpenTicket == ticket));

  bool _cancelPendingMobileSyncRemoteOpen({bool notifyParent = true}) {
    final request = _activeMobileSyncRemoteOpen;
    final ticket = _activeMobileSyncRemoteOpenTicket;
    if (request == null || ticket == null) return false;
    final origin = _mobileSyncRemoteOpenOrigin ?? _mobileLocation;
    _pendingSyncRemoteOpenGeneration++;
    _activeMobileSyncRemoteOpen = null;
    _activeMobileSyncRemoteOpenTicket = null;
    _mobileSyncRemoteOpenOrigin = null;
    final historyBase = _mobileSyncRemoteOpenHistoryBase;
    _mobileSyncRemoteOpenHistoryBase = null;
    if (historyBase != null && historyBase < _mobileLocationHistory.length) {
      _mobileLocationHistory.removeRange(
        historyBase,
        _mobileLocationHistory.length,
      );
    }
    _mobileLocation = origin;
    if (mounted) {
      // A target response may already be in flight; a fresh origin epoch makes
      // it harmless and restores the pre-sync loading/error state if needed.
      unawaited(_loadMobileFileManagerLocation(origin));
    }
    if (notifyParent) {
      widget.onPendingSyncRemoteOpenConsumed?.call(request, ticket);
    }
    return true;
  }

  bool _finishPendingSyncRemoteOpen(
    SyncRemoteOpenRequest request,
    int ticket,
    int generation, {
    bool restoreDesktopSnapshot = false,
  }) {
    final accepted =
        widget.onPendingSyncRemoteOpenConsumed?.call(request, ticket) ?? true;
    if (!accepted) return false;
    if (!_usesMobileNavigation) {
      _finishPendingDesktopSyncRemoteOpen(
        generation,
        restoreSnapshot: restoreDesktopSnapshot,
      );
      return true;
    }
    if (!identical(_activeMobileSyncRemoteOpen, request) ||
        _activeMobileSyncRemoteOpenTicket != ticket) {
      return false;
    }
    _activeMobileSyncRemoteOpen = null;
    _activeMobileSyncRemoteOpenTicket = null;
    _mobileSyncRemoteOpenOrigin = null;
    _mobileSyncRemoteOpenHistoryBase = null;
    return true;
  }

  Future<void> _applyPendingSyncRemoteOpen(
    SyncRemoteOpenRequest request,
    int ticket,
    int generation,
  ) async {
    final toastContext = context;
    if (_usesMobileNavigation &&
        !await _ensureMobileFileManagerInputRebound()) {
      return;
    }
    if (_buckets == null || _buckets!.isEmpty) {
      await _loadBuckets();
    }
    if (!_isCurrentPendingSyncRemoteOpen(request, ticket, generation)) return;
    final list = _buckets ?? const <FileManagerBucketEntry>[];
    FileManagerBucketEntry? entry;
    for (final e in list) {
      if (e.bucket.name != request.bucket) continue;
      if (e.profileName == request.profileName) {
        entry = e;
        break;
      }
    }
    if (entry == null) {
      for (final e in list) {
        if (e.bucket.name == request.bucket) {
          entry = e;
          break;
        }
      }
    }
    if (entry == null) {
      if (!toastContext.mounted ||
          !_isCurrentPendingSyncRemoteOpen(request, ticket, generation)) {
        return;
      }
      showAppErrorToast(
        toastContext,
        message: '未找到同步配置对应的存储桶（${request.bucket}）',
      );
      final mobileOrigin = !_usesMobileNavigation
          ? null
          : _mobileSyncRemoteOpenOrigin;
      final finished = _finishPendingSyncRemoteOpen(
        request,
        ticket,
        generation,
        restoreDesktopSnapshot: true,
      );
      // A replacement target has not pushed a new location yet. The request
      // it replaced may have left the shared loading state active, so reload
      // the saved origin rather than leaving an orphaned spinner behind.
      if (finished && mobileOrigin != null && mounted) {
        _mobileLocation = mobileOrigin;
        unawaited(_loadMobileFileManagerLocation(mobileOrigin));
      }
      return;
    }
    final prefix = _normalizeSyncRemotePrefix(request.remotePrefix);
    final ok = !_usesMobileNavigation
        ? await _loadObjects(
            entry,
            prefix,
            requestStillCurrent: () =>
                _isCurrentPendingSyncRemoteOpen(request, ticket, generation),
          )
        : await _pushAndLoadMobileFileManagerLocation(
            _MobileFileManagerLocation.objects(entry, prefix),
          );
    if (!_isCurrentPendingSyncRemoteOpen(request, ticket, generation)) return;
    // A failed target request already rendered a retry state; retaining the
    // shell ticket would only let a later rebuild replay the stale jump.
    _finishPendingSyncRemoteOpen(request, ticket, generation);
    if (!ok) return;
  }

  String _normalizeSyncRemotePrefix(String raw) {
    var p = raw.trim();
    if (p.isEmpty) return '';
    p = p.replaceAll('\\', '/');
    if (!p.endsWith('/')) {
      p = '$p/';
    }
    return p;
  }
}
