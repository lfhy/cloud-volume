part of 'file_manager_page.dart';

// Canonical file-manager chrome shared by desktop and Android.
extension _FileManagerPagePresentation on _FileManagerPageState {
  Widget _buildWorkspacePresentation(BuildContext context) {
    final theme = ShadTheme.of(context);
    final content = Padding(
      padding: _usesMobileNavigation
          ? const EdgeInsets.fromLTRB(16, 16, 16, 12)
          : const EdgeInsets.only(top: 56, left: 32, right: 32, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          const SizedBox(height: 16),
          Expanded(child: _buildFileTransferSurface(theme)),
        ],
      ),
    );
    return _usesMobileNavigation
        ? SafeArea(bottom: false, child: content)
        : content;
  }

  // Native desktop drop APIs are only mounted around the desktop presentation.
  Widget _buildFileTransferSurface(ShadThemeData theme) {
    final content = _buildContentWithMountLoading(theme);
    if (!isDesktopPlatform && !isWebPlatform) return content;
    return FileTransferClipboardRegion(
      enabled: _acceptsFileTransferInput,
      acceptsLocalFiles: _currentDirectoryWritable,
      onPasteLocalFiles: (paths) => unawaited(_uploadLocalPaths(paths)),
      onCopySelection: () => unawaited(_copySelectedObjectsToClipboard()),
      child: content,
    );
  }

  Widget _buildHeader(ShadThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isTrashHome) ...[
          Text(
            '回收站',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _showTrash ? '管理当前存储桶中的已删除对象。' : '选择一个存储桶进入它的回收站。',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
        ],
        FileManagerBreadcrumbBar(
          theme: theme,
          activeBucket: _presentationBucketLabel,
          breadcrumbs: _presentationBreadcrumbs,
          onBack:
              _usesMobileNavigation &&
                  (_mobileLocationHistory.isNotEmpty ||
                      _activeMobileSyncRemoteOpen != null)
              ? () => unawaited(_handleMobileFileManagerBack())
              : null,
          onOpenBucketList: () => unawaited(_openPresentationBucketList()),
          onOpenBucketRoot: () {
            final bucket = _presentationBucketEntry;
            if (bucket != null) {
              unawaited(_openPresentationBucketRoot(bucket));
            }
          },
          onOpenCrumb: (index) => unawaited(_openPresentationCrumb(index)),
        ),
        const SizedBox(height: 12),
        FileManagerActionBar(
          theme: theme,
          isGrid: _isGrid,
          showViewToggle: !_usesMobileNavigation,
          searchController: _searchController,
          searchEnabled: !_loading,
          searchPlaceholder: _showTrash
              ? '搜索回收站名称或原路径'
              : _activeBucket == null
              ? '搜索存储桶'
              : '搜索文件或目录',
          selectedCount: _selectedObjectKeys.length,
          batchDownloadEnabled: _selectedObjects.any((object) => !object.isDir),
          showingTrash: _showTrash,
          onToggleView: _toggleGridView,
          trashCloseLabel: _isTrashHome ? '返回存储桶' : '返回文件',
          onOpenTrash:
              _isTrashHome ||
                  _activeBucket == null ||
                  _loading ||
                  _showTrash ||
                  !_activeBucketTrashEnabled
              ? null
              : () => unawaited(_openPresentationTrash()),
          onCloseTrash: _activeBucket == null || _loading || !_showTrash
              ? null
              : () => unawaited(_closePresentationTrash()),
          onClearTrash:
              _activeBucket == null ||
                  _loading ||
                  !_showTrash ||
                  (_trashItems?.isEmpty ?? true)
              ? null
              : _clearBucketTrash,
          onCreateDirectory:
              _showTrash ||
                  _activeBucket == null ||
                  _loading ||
                  !_currentDirectoryWritable
              ? null
              : _createDirectory,
          onUpload:
              _showTrash ||
                  _activeBucket == null ||
                  _loading ||
                  !_currentDirectoryWritable
              ? null
              : _upload,
          onBatchDownload: _loading ? null : _downloadSelectedObjects,
          onBatchDelete: _loading || !_currentBucketWritable
              ? null
              : _deleteSelectedObjects,
          onClearSelection: _clearSelection,
        ),
      ],
    );
  }

  Widget _buildContent(ShadThemeData theme) {
    if (_loading) return _buildLoadingView(theme);
    if (_error != null) {
      return FileManagerErrorView(
        theme: theme,
        message: _error!,
        onRetry: () => unawaited(_retryPresentation()),
        secondaryActionLabel: _activeBucket == null ? '账号管理' : null,
        onSecondaryAction: _activeBucket == null
            ? () => widget.onOpenAccountManagement?.call()
            : null,
      );
    }
    if (_activeBucket == null) return _buildBucketView(theme);
    if (_showTrash) return _buildTrashView(theme);
    return _buildObjectView(theme);
  }

  Widget _buildLoadingView(ShadThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLoadingIndicator(size: 22, strokeWidth: 2.4),
          const SizedBox(height: 12),
          Text(
            _loadingMessage,
            style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
          ),
          if (_loadingDetail != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                _loadingDetail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.mutedForeground,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
