part of 'file_manager_object_browser.dart';

// 文件对象右键菜单：把空白区、单对象与多选批量菜单从渲染主体中拆开。

extension _FileManagerObjectBrowserMenus on FileManagerObjectBrowser {
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
