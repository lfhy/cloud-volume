part of 'file_manager_object_browser.dart';

// 文件对象右键菜单：把空白区、单对象与多选批量菜单从渲染主体中拆开。

extension _FileManagerObjectBrowserMenus on FileManagerObjectBrowser {
  Widget _buildListObjectRow(
    BuildContext context,
    ObjectInfo object,
    ShadThemeData theme,
    List<RemoteTask>? tasks,
    int index,
    bool compact,
  ) {
    final touchActions = Theme.of(context).platform == TargetPlatform.android;
    final menuHandle = touchActions ? DesktopContextMenuHandle() : null;
    return _selectionTarget(
      object,
      _wrapWithContextMenu(
        object,
        FileListTile(
          key: ValueKey('file-object-${object.key}'),
          leading: _leading(object, theme, listIconSize),
          title: _title(object),
          sizeLabel: _sizeLabel(object),
          statusWidget: _syncBadge(object, tasks),
          modifiedLabel: _modifiedLabel(object),
          onTap: _tapHandler(object),
          onDoubleTap: null,
          onTitleTap: _titleTapHandler(object),
          onSelectionTap: _selectionTapHandler(object),
          isSelected: _isSelected(object),
          showSelectionControl: _showsSelectionControl(object),
          showDivider: index != objects.length - 1 || loadingMore,
          deleting: _isDeleting(object),
          compact: compact,
          trailing: touchActions && !_isParentDirectory(object)
              ? _ObjectOverflowMenuButton(handle: menuHandle!)
              : null,
        ),
        handle: menuHandle,
      ),
    );
  }

  List<Widget> _buildBackgroundMenuItems() {
    if (selectedKeys.isNotEmpty) {
      return _buildSelectionMenuItems(selectedKeys.length);
    }
    return buildSelectionActionMenuItems(
      selectedCount: 0,
      onRefresh: onSelectionAction == null
          ? null
          : () => _runMenuAction(
              () => onSelectionAction!(FileSelectionAction.refresh),
            ),
      onUpload: onUpload == null ? null : () => _runMenuAction(onUpload!),
      onCreateDirectory: onCreateDirectory == null
          ? null
          : () => _runMenuAction(onCreateDirectory!),
    );
  }

  List<Widget> _buildObjectMenuItems(ObjectInfo object) {
    if (_isSelected(object) && selectedKeys.length > 1) {
      return _buildSelectionMenuItems(selectedKeys.length);
    }
    final objectItems = buildObjectActionMenuItems(
      object: object,
      onOpen: () => _runMenuAction(() => _openObject(object)),
      onDownload: object.isDir && !supportsDirectoryDownload
          ? null
          : () => _runMenuAction(() => onDownloadFile(object)),
      onShare: !supportsShareLinks || object.isDir
          ? null
          : () => _runMenuAction(
              () => onObjectAction(object, FileObjectAction.share),
            ),
      onCopy: readOnly
          ? null
          : () => _runMenuAction(
              () => onObjectAction(object, FileObjectAction.copy),
            ),
      onMove: readOnly
          ? null
          : () => _runMenuAction(
              () => onObjectAction(object, FileObjectAction.move),
            ),
      onRename: readOnly
          ? null
          : () => _runMenuAction(
              () => onObjectAction(object, FileObjectAction.rename),
            ),
      onDelete: readOnly
          ? null
          : () => _runMenuAction(
              () => onObjectAction(object, FileObjectAction.delete),
            ),
    );
    return <Widget>[
      ...objectItems.take(1),
      ...buildSelectionActionMenuItems(
        selectedCount: 0,
        onRefresh: onSelectionAction == null
            ? null
            : () => _runMenuAction(
                () => onSelectionAction!(FileSelectionAction.refresh),
              ),
        onUpload: onUpload == null ? null : () => _runMenuAction(onUpload!),
        onCreateDirectory: onCreateDirectory == null
            ? null
            : () => _runMenuAction(onCreateDirectory!),
      ),
      ...objectItems.skip(1),
    ];
  }

  List<Widget> _buildSelectionMenuItems(int selectedCount) {
    return buildSelectionActionMenuItems(
      selectedCount: selectedCount,
      onRefresh: selectedCount > 0 || onSelectionAction == null
          ? null
          : () => _runMenuAction(
              () => onSelectionAction!(FileSelectionAction.refresh),
            ),
      onUpload: onUpload == null ? null : () => _runMenuAction(onUpload!),
      onCreateDirectory: onCreateDirectory == null
          ? null
          : () => _runMenuAction(onCreateDirectory!),
      onDownload: onSelectionAction == null
          ? null
          : () => _runMenuAction(
              () => onSelectionAction!(FileSelectionAction.download),
            ),
      onCopy: readOnly || onSelectionAction == null
          ? null
          : () => _runMenuAction(
              () => onSelectionAction!(FileSelectionAction.copy),
            ),
      onMove: readOnly || onSelectionAction == null
          ? null
          : () => _runMenuAction(
              () => onSelectionAction!(FileSelectionAction.move),
            ),
      onDelete: readOnly || onSelectionAction == null
          ? null
          : () => _runMenuAction(
              () => onSelectionAction!(FileSelectionAction.delete),
            ),
    );
  }

  void _showBackgroundContextMenu(TapDownDetails details) {
    if (_buildBackgroundMenuItems().isEmpty) {
      return;
    }
    _backgroundContextMenuHandle.showAt(details.globalPosition);
  }
}

/// Responsive action affordance for the canonical compact file row.
class _ObjectOverflowMenuButton extends StatefulWidget {
  const _ObjectOverflowMenuButton({required this.handle});

  final DesktopContextMenuHandle handle;

  @override
  State<_ObjectOverflowMenuButton> createState() =>
      _ObjectOverflowMenuButtonState();
}

class _ObjectOverflowMenuButtonState extends State<_ObjectOverflowMenuButton> {
  final GlobalKey _buttonKey = GlobalKey();

  void _showMenu() {
    final buttonContext = _buttonKey.currentContext;
    final box = buttonContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    widget.handle.showAt(
      box.localToGlobal(Offset.zero),
      // Align the menu's 164px minimum width to the trailing button's edge.
      menuOffset: const Offset(-124, 40),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return KeyedSubtree(
      key: _buttonKey,
      child: ShadIconButton.ghost(
        width: 40,
        height: 40,
        iconSize: 18,
        icon: Icon(
          LucideIcons.ellipsisVertical,
          color: theme.colorScheme.mutedForeground,
        ),
        onPressed: _showMenu,
      ),
    );
  }
}
