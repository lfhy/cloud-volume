part of 'file_manager_page.dart';

// Desktop object browser composition stays separate from the shared runtime.
extension _FileManagerPageObjectView on _FileManagerPageState {
  Widget _buildObjectView(ShadThemeData theme) {
    if (_objects == null) return const SizedBox();
    final visibleObjects = _filteredVisibleObjects;
    if (visibleObjects.isEmpty && _hasSearchQuery) {
      return FileManagerEmptyState(
        theme: theme,
        icon: LucideIcons.folderSearch,
        text: '当前搜索没有结果',
      );
    }
    return FileManagerObjectBrowser(
      objects: visibleObjects,
      prefix: _prefix,
      isGrid: _usesMobileNavigation ? false : _isGrid,
      scrollController: _contentScrollController,
      hasMore: _objectsHasMore,
      loadingMore: _pagingObjects,
      selectedKeys: _selectedObjectKeys,
      deletingKeys: _deletingObjectKeys,
      // WebDAV permissions can differ per directory; hide and reject writes
      // until the current directory probe confirms this location is writable.
      readOnly: !_currentDirectoryWritable,
      supportsDirectoryDownload:
          widget.api.capabilities.supportsDownloadDirectory,
      supportsBrowserTransfers:
          widget.api.capabilities.supportsBrowserTransfers,
      gridIconSize: _FileManagerPageState._gridIconSize,
      listIconSize: _FileManagerPageState._listIconSize,
      mountedToDesktop: _activeMountStatus?.mounted ?? false,
      mountBucketName: _activeBucket,
      profileId: _activeConfig.profileId,
      // Android has no mounted local mirror; a green "synced" badge would be
      // misleading and crowds the compact metadata row.
      showSyncStatus: !_usesMobileNavigation,
      mobilePresentation: _usesMobileNavigation,
      onOpenDirectory: (prefix) =>
          unawaited(_openPresentationDirectory(prefix)),
      onOpenFile: (object) => unawaited(_openObject(object)),
      onDownloadFile: (object) => unawaited(_downloadObject(object)),
      onNavigateUp: () => unawaited(_navigatePresentationUp()),
      onToggleSelection: _toggleObjectSelection,
      onSelectionSetChanged: _replaceSelectedObjects,
      onToggleSelectAll: _toggleSelectAllObjects,
      onCreateDirectory: _showTrash || _loading || !_currentDirectoryWritable
          ? null
          : () => unawaited(_createDirectory()),
      onUpload: _showTrash || _loading || !_currentDirectoryWritable
          ? null
          : () => unawaited(_upload()),
      onClearSelection: _clearSelection,
      onSelectionContextRequested: _selectObjectsForContextMenu,
      onSelectionAction: (action) =>
          unawaited(_handleSelectedObjectsAction(action)),
      supportsShareLinks: _activeConfig.supportsShareLinks,
      onObjectAction: (object, action) =>
          unawaited(_handleObjectAction(object, action)),
    );
  }
}
