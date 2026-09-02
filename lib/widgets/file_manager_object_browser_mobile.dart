part of 'file_manager_object_browser.dart';

// Android object rows mirror the compact bucket surface while keeping the
// desktop table, selection model, and mutation callbacks shared.

class _MobileObjectMenuAction {
  const _MobileObjectMenuAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

extension _FileManagerObjectBrowserMobilePresentation
    on FileManagerObjectBrowser {
  Widget _buildMobileList(
    BuildContext context,
    List<ObjectInfo> objects,
    ShadThemeData theme,
    List<RemoteTask>? tasks,
  ) {
    return ListView.builder(
      controller: scrollController,
      itemCount: objects.length + (loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= objects.length) {
          return _buildListLoadingRow(theme);
        }
        return _buildMobileObjectRow(
          context,
          objects[index],
          theme,
          tasks,
          index,
          objects.length,
        );
      },
    );
  }

  Widget _buildMobileObjectRow(
    BuildContext context,
    ObjectInfo object,
    ShadThemeData theme,
    List<RemoteTask>? tasks,
    int index,
    int objectCount,
  ) {
    final parent = _isParentDirectory(object);
    final deleting = _isDeleting(object);
    final canOpenMenu = !parent && !deleting;
    final usesSelectionActions = _isSelected(object) && selectedKeys.length > 1;
    final menuActions = canOpenMenu
        ? _buildMobileObjectActions(object)
        : const <_MobileObjectMenuAction>[];
    final menuTitle = usesSelectionActions
        ? '已选 ${selectedKeys.length} 项'
        : _title(object);
    final subtitle = parent
        ? '返回上一级'
        : deleting
        ? ''
        : object.isDir
        ? '文件夹'
        : '';

    return _selectionTarget(
      object,
      FileListTile(
        key: ValueKey('file-object-${object.key}'),
        leading: _leading(object, theme, 28),
        title: _title(object),
        subtitleLabel: subtitle,
        sizeLabel: _sizeLabel(object),
        statusWidget: _syncBadge(object, tasks),
        modifiedLabel: _modifiedLabel(object),
        onTap: _tapHandler(object),
        onLongPress: canOpenMenu
            ? () => _showMobileObjectMenu(context, object, menuTitle)
            : null,
        onDoubleTap: null,
        onTitleTap: _titleTapHandler(object),
        onSelectionTap: _selectionTapHandler(object),
        isSelected: _isSelected(object),
        showSelectionControl: _showsSelectionControl(object),
        showDivider: index != objectCount - 1 || loadingMore,
        deleting: deleting,
        compact: true,
        trailing: canOpenMenu
            ? _MobileObjectOverflowMenuButton(
                actions: menuActions,
                objectLabel: _title(object),
                actionSheetTitle: menuTitle,
              )
            : null,
      ),
    );
  }

  List<_MobileObjectMenuAction> _buildMobileObjectActions(ObjectInfo object) {
    if (_isSelected(object) && selectedKeys.length > 1) {
      return _buildMobileSelectionActions();
    }
    return <_MobileObjectMenuAction>[
      _MobileObjectMenuAction(
        label: object.isDir ? '打开' : '预览',
        icon: object.isDir ? LucideIcons.folderOpen : LucideIcons.eye,
        onPressed: () => _runMobileMenuAction(() => _openObject(object)),
      ),
      if (!object.isDir || supportsDirectoryDownload)
        _MobileObjectMenuAction(
          label: '下载',
          icon: LucideIcons.download,
          onPressed: () => _runMobileMenuAction(() => onDownloadFile(object)),
        ),
      if (supportsShareLinks && !object.isDir)
        _MobileObjectMenuAction(
          label: '创建分享',
          icon: LucideIcons.share2,
          onPressed: () => _runMobileMenuAction(
            () => onObjectAction(object, FileObjectAction.share),
          ),
        ),
      if (!readOnly) ...[
        _MobileObjectMenuAction(
          label: '复制到...',
          icon: LucideIcons.copy,
          onPressed: () => _runMobileMenuAction(
            () => onObjectAction(object, FileObjectAction.copy),
          ),
        ),
        _MobileObjectMenuAction(
          label: '移动到...',
          icon: LucideIcons.move,
          onPressed: () => _runMobileMenuAction(
            () => onObjectAction(object, FileObjectAction.move),
          ),
        ),
        _MobileObjectMenuAction(
          label: '重命名',
          icon: LucideIcons.pencil,
          onPressed: () => _runMobileMenuAction(
            () => onObjectAction(object, FileObjectAction.rename),
          ),
        ),
        _MobileObjectMenuAction(
          label: '删除',
          icon: LucideIcons.trash2,
          onPressed: () => _runMobileMenuAction(
            () => onObjectAction(object, FileObjectAction.delete),
          ),
        ),
      ],
    ];
  }

  List<_MobileObjectMenuAction> _buildMobileSelectionActions() {
    final actions = <_MobileObjectMenuAction>[];
    final selectionAction = onSelectionAction;
    if (selectionAction != null) {
      actions.addAll([
        if (_canDownloadSelectedObjects)
          _MobileObjectMenuAction(
            label: '批量下载',
            icon: LucideIcons.download,
            onPressed: () => _runMobileMenuAction(
              () => selectionAction(FileSelectionAction.download),
            ),
          ),
        if (!readOnly)
          _MobileObjectMenuAction(
            label: '批量复制到...',
            icon: LucideIcons.copy,
            onPressed: () => _runMobileMenuAction(
              () => selectionAction(FileSelectionAction.copy),
            ),
          ),
        if (!readOnly)
          _MobileObjectMenuAction(
            label: '批量移动到...',
            icon: LucideIcons.move,
            onPressed: () => _runMobileMenuAction(
              () => selectionAction(FileSelectionAction.move),
            ),
          ),
        if (!readOnly)
          _MobileObjectMenuAction(
            label: '批量删除',
            icon: LucideIcons.trash2,
            onPressed: () => _runMobileMenuAction(
              () => selectionAction(FileSelectionAction.delete),
            ),
          ),
      ]);
    }
    if (onClearSelection != null) {
      actions.add(
        _MobileObjectMenuAction(
          label: '取消选择',
          icon: LucideIcons.x,
          onPressed: () => _runMobileMenuAction(onClearSelection!),
        ),
      );
    }
    return actions;
  }

  bool get _canDownloadSelectedObjects {
    final selected = objects.where(
      (object) =>
          !_isParentDirectory(object) && selectedKeys.contains(object.key),
    );
    var hasFile = false;
    var hasDirectory = false;
    for (final object in selected) {
      if (object.isDir) {
        hasDirectory = true;
      } else {
        hasFile = true;
      }
    }
    if (hasFile) return true;
    // Browser transfer flows intentionally return early for directory-only
    // selections; expose that action only when the native recursive path is
    // available.
    return hasDirectory &&
        supportsDirectoryDownload &&
        !supportsBrowserTransfers;
  }

  void _runMobileMenuAction(VoidCallback action) {
    DesktopContextMenuRegistry.dismiss(_objectContextMenuGroup);
    action();
  }

  Future<void> _showMobileObjectMenu(
    BuildContext context,
    ObjectInfo object,
    String title,
  ) async {
    final actions = _buildMobileObjectActions(object);
    if (actions.isEmpty) return;
    await _showMobileObjectActionSheet(context, title, actions);
  }
}

/// 48dp Android row-end affordance; the sheet uses the same width and inset
/// contract as the bucket browser's mobile overflow menu.
class _MobileObjectOverflowMenuButton extends StatelessWidget {
  const _MobileObjectOverflowMenuButton({
    required this.actions,
    required this.objectLabel,
    required this.actionSheetTitle,
  });

  final List<_MobileObjectMenuAction> actions;
  final String objectLabel;
  final String actionSheetTitle;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Semantics(
      label: '$objectLabel 的更多操作',
      child: ShadIconButton.ghost(
        icon: Icon(
          LucideIcons.ellipsisVertical,
          size: 18,
          color: theme.colorScheme.mutedForeground,
        ),
        width: 48,
        height: 48,
        iconSize: 18,
        onPressed: actions.isEmpty
            ? null
            : () => _showMobileObjectActionSheet(
                context,
                actionSheetTitle,
                actions,
              ),
      ),
    );
  }
}

Future<void> _showMobileObjectActionSheet(
  BuildContext context,
  String objectLabel,
  List<_MobileObjectMenuAction> actions,
) async {
  await showAppModal<void>(
    context: context,
    builder: (dialogContext) {
      // Keep the sheet inside horizontal cutout insets and preserve a full
      // width pressed surface with a fixed 16dp icon inset.
      final horizontalSafeArea = MediaQuery.paddingOf(dialogContext).horizontal;
      const actionHorizontalPadding = 16.0;
      final menuWidth =
          (MediaQuery.sizeOf(dialogContext).width - horizontalSafeArea - 60)
              .clamp(1.0, double.infinity)
              .toDouble();
      final actionContentWidth = (menuWidth - actionHorizontalPadding * 2)
          .clamp(0.0, double.infinity)
          .toDouble();
      return AppShadDialog(
        title: Text(objectLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
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
