// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

/// A logical Android file location. It is committed before a remote request
/// completes so Back can return from loading and error states as well.
enum _MobileFileManagerLocationKind { bucketList, objects, trash }

class _MobileFileManagerLocation {
  const _MobileFileManagerLocation._(
    this.kind, {
    this.bucket,
    this.prefix = '',
  });

  const _MobileFileManagerLocation.bucketList()
    : this._(_MobileFileManagerLocationKind.bucketList);

  const _MobileFileManagerLocation.objects(
    FileManagerBucketEntry bucket,
    String prefix,
  ) : this._(
        _MobileFileManagerLocationKind.objects,
        bucket: bucket,
        prefix: prefix,
      );

  const _MobileFileManagerLocation.trash(FileManagerBucketEntry bucket)
    : this._(_MobileFileManagerLocationKind.trash, bucket: bucket);

  final _MobileFileManagerLocationKind kind;
  final FileManagerBucketEntry? bucket;
  final String prefix;

  bool matches(_MobileFileManagerLocation other) {
    return kind == other.kind &&
        bucket?.id == other.bucket?.id &&
        prefix == other.prefix;
  }
}

/// Couples a mobile listing request to the location that started it.
class _MobileFileManagerRequest {
  const _MobileFileManagerRequest({
    required this.location,
    required this.epoch,
    required this.inputGeneration,
  });

  final _MobileFileManagerLocation location;
  final int epoch;
  final int inputGeneration;

  bool isCurrent(_FileManagerPageState state) =>
      epoch == state._mobileNavigationEpoch &&
      inputGeneration == state._mobileInputGeneration &&
      state._mobileLocation.matches(location);
}

/// Rebound Android locations retain only buckets resolved from fresh inputs.
class _ReboundMobileFileManagerLocations {
  const _ReboundMobileFileManagerLocations({
    required this.current,
    required this.history,
  });

  final _MobileFileManagerLocation current;
  final List<_MobileFileManagerLocation> history;
}

/// Shared file-browser runtime. Desktop UX is the canonical renderer; Android
/// enables its navigation semantics without introducing a second page surface.
class FileManagerWorkspace extends StatefulWidget {
  const FileManagerWorkspace({
    super.key,
    required this.api,
    required this.config,
    required this.profiles,
    required this.onRefresh,
    this.homeView = FileManagerHomeView.files,
    this.pendingSyncRemoteOpen,
    this.pendingSyncRemoteOpenGeneration = 0,
    this.onPendingSyncRemoteOpenConsumed,
    this.onOpenAccountManagement,
    this.mobileNavigation = false,
    this.navigation,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final List<ProfileInfo> profiles;
  final VoidCallback onRefresh;
  final FileManagerHomeView homeView;
  final SyncRemoteOpenRequest? pendingSyncRemoteOpen;
  final int pendingSyncRemoteOpenGeneration;
  final SyncRemoteOpenConsumer? onPendingSyncRemoteOpenConsumed;
  final VoidCallback? onOpenAccountManagement;
  final bool mobileNavigation;
  final MobileFileManagerNavigation? navigation;

  @override
  State<FileManagerWorkspace> createState() => _FileManagerPageState();
}

/// Owns Android's logical file-location transitions independently of either
/// presentation. It is also used by external navigation such as sync tasks.
extension _FileManagerPageMobileNavigation on _FileManagerPageState {
  Future<bool> _handleMobileFileManagerBack() async {
    if (_cancelPendingMobileSyncRemoteOpen()) return true;
    return await _navigateBackMobileFileManagerLocation();
  }

  Future<bool> _pushAndLoadMobileFileManagerLocation(
    _MobileFileManagerLocation target,
  ) async {
    if (!await _ensureMobileFileManagerInputRebound()) return false;
    final targetAfterRebind = _rebindMobileFileManagerLocation(
      target,
      <String, FileManagerBucketEntry>{
        for (final entry in _buckets ?? const <FileManagerBucketEntry>[])
          entry.id: entry,
      },
    );
    if (targetAfterRebind == null) return false;
    final current = _mobileLocation;
    if (!current.matches(targetAfterRebind)) {
      _mobileLocationHistory.add(current);
      _mobileLocation = targetAfterRebind;
    }
    return await _loadMobileFileManagerLocation(targetAfterRebind);
  }

  Future<bool> _navigateBackMobileFileManagerLocation() async {
    // Do not let Back consume history using the previous profile's bucket
    // entry while a bootstrap refresh is still rebinding it.
    if (!await _ensureMobileFileManagerInputRebound()) return true;
    final history = _mobileLocationHistory;
    if (history.isEmpty) return false;
    final previous = history.removeLast();
    _mobileLocation = previous;
    await _loadMobileFileManagerLocation(previous);
    return true;
  }

  Future<bool> _loadMobileFileManagerLocation(
    _MobileFileManagerLocation location, {
    bool forceRefresh = false,
    int? inputGeneration,
  }) async {
    if (_usesMobileNavigation && inputGeneration == null) {
      if (!await _ensureMobileFileManagerInputRebound()) return false;
    }
    if (inputGeneration != null && inputGeneration != _mobileInputGeneration) {
      return false;
    }
    if (_usesMobileNavigation) {
      final rebound = _rebindMobileFileManagerLocation(
        location,
        <String, FileManagerBucketEntry>{
          for (final entry in _buckets ?? const <FileManagerBucketEntry>[])
            entry.id: entry,
        },
      );
      if (rebound == null) return false;
      if (_mobileLocation.matches(location) &&
          !identical(_mobileLocation.bucket, rebound.bucket)) {
        _mobileLocation = rebound;
      }
      location = rebound;
    }
    final epoch = ++_mobileNavigationEpoch;
    return await switch (location.kind) {
      _MobileFileManagerLocationKind.bucketList => _loadBuckets(
        force: forceRefresh,
        mobileNavigationEpoch: epoch,
      ),
      _MobileFileManagerLocationKind.objects => _loadObjects(
        location.bucket!,
        location.prefix,
        forceRefresh: forceRefresh,
        mobileNavigationEpoch: epoch,
      ),
      _MobileFileManagerLocationKind.trash => _openBucketTrash(
        bucket: location.bucket!,
        mobileNavigationEpoch: epoch,
      ),
    };
  }

  /// Starts a same-location reload that must invalidate older pagination.
  /// Callers verify [request] first; desktop has no mobile request and keeps
  /// its established reload behavior.
  _MobileFileManagerRequest? _supersedeMobileFileManagerRequest(
    _MobileFileManagerRequest? request,
  ) {
    if (request == null) return null;
    assert(_isCurrentMobileFileManagerRequest(request));
    return _MobileFileManagerRequest(
      location: request.location,
      epoch: ++_mobileNavigationEpoch,
      inputGeneration: request.inputGeneration,
    );
  }
}
