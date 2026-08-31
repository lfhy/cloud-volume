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
      isGrid: _isGrid,
      scrollController: _contentScrollController,
      hasMore: _objectsHasMore,
      loadingMore: _pagingObjects,
      selectedKeys: _selectedObjectKeys,
      deletingKeys: _deletingObjectKeys,
      readOnly: _activeBucketReadOnly,
      supportsDirectoryDownload:
          widget.api.capabilities.supportsDownloadDirectory,
      gridIconSize: _FileManagerPageState._gridIconSize,
      listIconSize: _FileManagerPageState._listIconSize,
      mountedToDesktop: _activeMountStatus?.mounted ?? false,
      mountBucketName: _activeBucket,
      profileId: _activeConfig.profileId,
      showSyncStatus: true,
      onOpenDirectory: (prefix) => unawaited(_navToPrefix(prefix)),
      onOpenFile: (object) => unawaited(_openObject(object)),
      onDownloadFile: (object) => unawaited(_downloadObject(object)),
      onNavigateUp: () => unawaited(_navUp()),
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
