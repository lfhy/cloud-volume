part of 'file_manager_page.dart';

// Presentation navigation keeps desktop chrome aligned with Android's
// location stack instead of maintaining a separate mobile interaction model.
extension _FileManagerPagePresentationNavigation on _FileManagerPageState {
  Future<void> _openPresentationBucketList() {
    if (!_usesMobileNavigation) return _loadBuckets(force: true);
    return _pushAndLoadMobileFileManagerLocation(
      const _MobileFileManagerLocation.bucketList(),
    );
  }

  Future<void> _openPresentationBucket(FileManagerBucketEntry bucket) {
    if (!_usesMobileNavigation) return _navToBucket(bucket);
    final location = _isTrashHome
        ? _MobileFileManagerLocation.trash(bucket)
        : _MobileFileManagerLocation.objects(bucket, '');
    return _pushAndLoadMobileFileManagerLocation(location);
  }

  Future<void> _openPresentationBucketRoot(FileManagerBucketEntry bucket) {
    if (!_usesMobileNavigation) return _navToBucket(bucket);
    return _pushAndLoadMobileFileManagerLocation(
      _MobileFileManagerLocation.objects(bucket, ''),
    );
  }

  Future<void> _openPresentationDirectory(String prefix) {
    final bucket = _activeBucketEntry;
    if (bucket == null) return Future<void>.value();
    if (!_usesMobileNavigation) return _navToPrefix(prefix);
    return _pushAndLoadMobileFileManagerLocation(
      _MobileFileManagerLocation.objects(bucket, prefix),
    );
  }

  Future<void> _openPresentationCrumb(int index) {
    final bucket = _activeBucketEntry;
    if (bucket == null) return Future<void>.value();
    if (!_usesMobileNavigation) return _navCrumb(index);
    if (index < 0) return _openPresentationBucketList();
    final prefix = _breadcrumbs
        .take(index + 1)
        .map((segment) => '$segment/')
        .join();
    return _pushAndLoadMobileFileManagerLocation(
      _MobileFileManagerLocation.objects(bucket, prefix),
    );
  }

  Future<void> _openPresentationTrash([FileManagerBucketEntry? bucket]) {
    final target = bucket ?? _activeBucketEntry;
    if (target == null) return Future<void>.value();
    if (!_usesMobileNavigation) return _openBucketTrash(bucket: target);
    return _pushAndLoadMobileFileManagerLocation(
      _MobileFileManagerLocation.trash(target),
    );
  }

  Future<void> _closePresentationTrash() async {
    if (!_usesMobileNavigation) {
      await _closeBucketTrash();
      return;
    }
    if (!await _navigateBackMobileFileManagerLocation()) {
      await _openPresentationBucketList();
    }
  }

  Future<void> _navigatePresentationUp() async {
    if (!_usesMobileNavigation) {
      await _navUp();
      return;
    }
    await _handleMobileFileManagerBack();
  }

  Future<void> _retryPresentation() {
    if (_usesMobileNavigation) {
      return _loadMobileFileManagerLocation(
        _mobileLocation,
        forceRefresh: true,
      );
    }
    if (_activeBucketEntry == null) return _loadBuckets(force: true);
    return _showTrash
        ? _openBucketTrash(bucket: _activeBucketEntry!)
        : _loadObjects(_activeBucketEntry!, _prefix, forceRefresh: true);
  }
}
