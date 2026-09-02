part of 'file_manager_page.dart';

// Android-only file-manager chrome. It shares the workspace state and actions
// with desktop, while keeping mobile navigation and density independently tuned.
extension _MobileFileManagerPresentation on _FileManagerPageState {
  Widget _buildMobileWorkspacePresentation(BuildContext context) {
    final theme = ShadTheme.of(context);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMobileHeader(theme),
          const SizedBox(height: 14),
          _buildMobileSearch(theme),
          const SizedBox(height: 10),
          _buildMobileActions(theme),
          const SizedBox(height: 12),
          Expanded(child: _buildFileTransferSurface(theme)),
        ],
      ),
    );
    return SafeArea(bottom: false, child: content);
  }

  Widget _buildMobileHeader(ShadThemeData theme) {
    final bucket = _presentationBucketEntry;
    final subtitle = bucket == null
        ? (_isTrashHome ? '选择一个存储桶' : '所有存储桶')
        : _showTrash
        ? '${bucket.label} · 回收站'
        : _presentationBreadcrumbs.isEmpty
        ? bucket.label
        : _presentationBreadcrumbs.last;
    final canGoBack =
        _mobileLocationHistory.isNotEmpty ||
        _activeMobileSyncRemoteOpen != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (canGoBack) ...[
          AppTooltip(
            message: '返回',
            child: ShadIconButton.ghost(
              width: 48,
              height: 48,
              iconSize: 20,
              icon: Icon(
                LucideIcons.chevronLeft,
                color: theme.colorScheme.foreground,
              ),
              onPressed: () => unawaited(_handleMobileFileManagerBack()),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isTrashHome ? '回收站' : '文件管理',
                style: theme.textTheme.h3.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 23,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.mutedForeground,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileSearch(ShadThemeData theme) {
    final placeholder = _showTrash
        ? '搜索回收站名称或原路径'
        : _activeBucket == null
        ? '搜索存储桶'
        : '搜索文件或目录';
    return ShadInput(
      controller: _searchController,
      enabled: !_loading,
      placeholder: Text(placeholder),
      leading: Icon(
        LucideIcons.search,
        size: 17,
        color: theme.colorScheme.mutedForeground,
      ),
      trailing: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) {
          if (value.text.isEmpty) return const SizedBox.shrink();
          return GestureDetector(
            onTap: _searchController.clear,
            child: Icon(
              LucideIcons.x,
              size: 16,
              color: theme.colorScheme.mutedForeground,
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileActions(ShadThemeData theme) {
    final actions = <Widget>[];
    void addAction(String label, IconData icon, VoidCallback? callback) {
      if (callback == null) return;
      actions.add(
        SizedBox(
          height: 48,
          child: ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: callback,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: theme.colorScheme.primary),
                const SizedBox(width: 5),
                Text(label),
              ],
            ),
          ),
        ),
      );
    }

    if (_showTrash) {
      addAction(
        '返回文件',
        LucideIcons.folderOpen,
        _activeBucket == null || _loading
            ? null
            : () => unawaited(_closePresentationTrash()),
      );
      addAction(
        '清空回收站',
        LucideIcons.trash,
        _loading || (_trashItems?.isEmpty ?? true) ? null : _clearBucketTrash,
      );
    } else if (_activeBucket != null) {
      addAction(
        '回收站',
        LucideIcons.trash2,
        _isTrashHome || _loading || !_activeBucketTrashEnabled
            ? null
            : () => unawaited(_openPresentationTrash()),
      );
      addAction(
        '新建目录',
        Icons.create_new_folder_rounded,
        _loading || !_currentDirectoryWritable ? null : _createDirectory,
      );
      addAction(
        '上传',
        LucideIcons.upload,
        _loading || !_currentDirectoryWritable ? null : _upload,
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: actions),
      ),
    );
  }
}
