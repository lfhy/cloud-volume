part of 'file_manager_page.dart';

// Android-only file-manager chrome. It shares the workspace state and actions
// with desktop, while keeping mobile navigation and density independently tuned.
class _MobileFileAction {
  const _MobileFileAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

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
    return SafeArea(bottom: false, child: content);
  }

  Widget _buildMobileHeader(ShadThemeData theme) {
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
          // The visible plus is a compact entry to context-sensitive actions;
          // the semantic label explains that it can also open trash actions.
          Semantics(
            label: '文件操作',
            child: ShadIconButton.ghost(
              width: 48,
              height: 48,
              iconSize: 22,
              icon: Icon(LucideIcons.plus, color: theme.colorScheme.primary),
              onPressed: () => unawaited(_showMobileActionSheet(actions)),
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

  List<_MobileFileAction> get _mobileActions {
    final actions = <_MobileFileAction>[];
    if (_showTrash) {
      if (_activeBucket != null && !_loading) {
        actions.add(
          _MobileFileAction(
            label: '返回文件',
            icon: LucideIcons.folderOpen,
            onPressed: () => unawaited(_closePresentationTrash()),
          ),
        );
      }
      if (!_loading && !(_trashItems?.isEmpty ?? true)) {
        actions.add(
          _MobileFileAction(
            label: '清空回收站',
            icon: LucideIcons.trash,
            onPressed: _clearBucketTrash,
          ),
        );
      }
    } else if (_activeBucket != null) {
      if (!_isTrashHome && !_loading && _activeBucketTrashEnabled) {
        actions.add(
          _MobileFileAction(
            label: '回收站',
            icon: LucideIcons.trash2,
            onPressed: () => unawaited(_openPresentationTrash()),
          ),
        );
      }
      if (!_loading && _currentDirectoryWritable) {
        actions.addAll([
          _MobileFileAction(
            label: '新建目录',
            icon: Icons.create_new_folder_rounded,
            onPressed: _createDirectory,
          ),
          _MobileFileAction(
            label: '上传',
            icon: LucideIcons.upload,
            onPressed: _upload,
          ),
        ]);
      }
    }
    return actions;
  }

  Future<void> _showMobileActionSheet(List<_MobileFileAction> actions) async {
    if (actions.isEmpty) return;
    await showAppModal<void>(
      context: context,
      builder: (dialogContext) {
        // Keep sheet rows full-width inside horizontal cutouts while matching
        // the 16dp icon inset used by bucket and object action drawers.
        final horizontalSafeArea = MediaQuery.paddingOf(
          dialogContext,
        ).horizontal;
        const actionHorizontalPadding = 16.0;
        final menuWidth =
            (MediaQuery.sizeOf(dialogContext).width - horizontalSafeArea - 60)
                .clamp(1.0, double.infinity)
                .toDouble();
        final actionContentWidth = (menuWidth - actionHorizontalPadding * 2)
            .clamp(0.0, double.infinity)
            .toDouble();
        return AppShadDialog(
          title: Text(_showTrash ? '回收站操作' : '文件操作'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final action in actions) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: ShadButton.ghost(
                    width: menuWidth,
                    padding: const EdgeInsets.symmetric(
                      horizontal: actionHorizontalPadding,
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      action.onPressed();
                    },
                    child: SizedBox(
                      width: actionContentWidth,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 48,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Icon(action.icon, size: 17),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                action.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        );
      },
    );
  }
}
