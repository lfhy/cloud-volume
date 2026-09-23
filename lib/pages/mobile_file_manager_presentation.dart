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
          const SizedBox(height: 12),
          Expanded(child: _buildFileTransferSurface(theme)),
        ],
      ),
    );
    // 向 shell 报告选中态(两态模型):选中时底部导航栏让位给动作条。
    MobileSelectionActivity.instance.report(
      SidebarItem.fileManager,
      _mobileSelectionActive,
    );
    // 选中态底部动作条全宽贴底(百度式):移出页边距列,自带底部安全区。
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(child: content),
          _buildMobileSelectionBar(),
        ],
      ),
    );
  }

  Widget _buildMobileHeader(ShadThemeData theme) {
    // 两态选择模型:选中态头部整体变形(取消/已选中 N 个/全选),返回钮与
    // 页面动作入口让位——退出选中用「取消」,系统 Back 也会先清空选择。
    final selectionHeader = _buildMobileSelectionHeader();
    if (selectionHeader != null) {
      return selectionHeader;
    }
    final bucket = _presentationBucketEntry;
    final subtitle = bucket == null
        ? (_isTrashHome ? '选择一个存储桶' : '浏览和管理远程存储中的文件。')
        : _showTrash
        ? '${bucket.label} · 回收站'
        : _presentationBreadcrumbs.isEmpty
        ? bucket.label
        : _presentationBreadcrumbs.last;
    final canGoBack =
        _mobileLocationHistory.isNotEmpty ||
        _activeMobileSyncRemoteOpen != null;
    final actions = _mobileActions;
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
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 8),
          // The visible plus is a compact entry to context-sensitive file
          // actions. The global trash remains a separate navigation target.
          Semantics(
            label: '文件操作',
            child: ShadIconButton.ghost(
              width: 48,
              height: 48,
              iconSize: 22,
              icon: Icon(LucideIcons.plus, color: theme.colorScheme.primary),
              onPressed: () => unawaited(
                showMobileActionSheet(
                  context,
                  title: _showTrash ? '回收站操作' : '文件操作',
                  actions: actions,
                ),
              ),
            ),
          ),
        ],
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

  List<MobilePageAction> get _mobileActions {
    final actions = <MobilePageAction>[];
    // 回收站视图的页面级入口(返回文件/清空回收站)按用户裁决恢复;
    // 文件视图提供 新建目录/上传。
    if (_showTrash) {
      if (_activeBucket != null && !_loading) {
        actions.add(
          MobilePageAction(
            label: '返回文件',
            icon: LucideIcons.folderOpen,
            onPressed: () => unawaited(_closePresentationTrash()),
          ),
        );
      }
      if (!_loading && !(_trashItems?.isEmpty ?? true)) {
        actions.add(
          MobilePageAction(
            label: '清空回收站',
            icon: LucideIcons.trash,
            onPressed: _clearBucketTrash,
          ),
        );
      }
    } else if (_activeBucket != null) {
      if (!_loading && _currentDirectoryWritable) {
        actions.addAll([
          MobilePageAction(
            label: '新建目录',
            icon: Icons.create_new_folder_rounded,
            onPressed: _createDirectory,
          ),
          MobilePageAction(
            label: '上传',
            icon: LucideIcons.upload,
            onPressed: _upload,
          ),
        ]);
      }
    }
    return actions;
  }
}
