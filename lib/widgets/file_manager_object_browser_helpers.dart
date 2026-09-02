part of 'file_manager_object_browser.dart';

// Shared object-row helpers keep the main browser focused on layout selection.
// Desktop and Android presentations call these methods so interaction and
// object-state rules cannot drift between the two surfaces.

extension _FileManagerObjectBrowserHelpers on FileManagerObjectBrowser {
  Widget _leading(ObjectInfo object, ShadThemeData theme, double size) {
    if (_isParentDirectory(object)) {
      return SizedBox.square(
        dimension: size,
        child: Center(
          child: Icon(
            Icons.arrow_upward_rounded,
            size: size * 0.52,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }
    return LocalCloudPanFileIcon(
      name: object.displayName,
      isDirectory: object.isDir,
      size: size,
    );
  }

  String _title(ObjectInfo object) {
    return _isParentDirectory(object) ? '..' : object.displayName;
  }

  String _subtitle(ObjectInfo object, {bool forGrid = false}) {
    if (_isParentDirectory(object)) return '返回上一级';
    if (_isDeleting(object)) return '删除中';
    if (object.isDir) return forGrid ? '' : '文件夹';
    return forGrid
        ? object.sizeText
        : '${object.sizeText}  ${object.lastModified}';
  }

  String _sizeLabel(ObjectInfo object) {
    if (_isParentDirectory(object) || object.isDir || _isDeleting(object)) {
      return '';
    }
    return object.sizeText;
  }

  String _modifiedLabel(ObjectInfo object) {
    if (_isDeleting(object)) return '删除中';
    if (_isParentDirectory(object) || object.lastModified.isEmpty) return '';
    return object.lastModified;
  }

  VoidCallback _tapHandler(ObjectInfo object) {
    return () {
      if (_isDeleting(object)) {
        return;
      }
      if (_dismissActiveContextMenu()) {
        return;
      }
      if (_shouldToggleSelectionOnClick(object)) {
        onToggleSelection(object);
        return;
      }
      _openObject(object);
    };
  }

  VoidCallback _titleTapHandler(ObjectInfo object) {
    return () {
      if (_dismissActiveContextMenu()) {
        return;
      }
      if (_shouldToggleSelectionOnClick(object)) {
        onToggleSelection(object);
        return;
      }
      _openObject(object);
    };
  }

  VoidCallback? _selectionTapHandler(ObjectInfo object) {
    if (!_showsSelectionControl(object)) {
      return null;
    }
    return () {
      if (_isDeleting(object)) {
        return;
      }
      if (_dismissActiveContextMenu()) {
        return;
      }
      onToggleSelection(object);
    };
  }

  GestureTapDownCallback? _secondaryTapHandler(ObjectInfo object) {
    if (_isParentDirectory(object) || _isDeleting(object)) {
      return null;
    }
    return (_) {
      if (!_isSelected(object)) {
        onSelectionContextRequested?.call(object);
      }
    };
  }

  Widget _wrapWithContextMenu(
    ObjectInfo object,
    Widget child, {
    DesktopContextMenuHandle? handle,
  }) {
    if (_isParentDirectory(object) || _isDeleting(object)) {
      return child;
    }
    return DesktopContextMenuRegion(
      groupId: _objectContextMenuGroup,
      items: _buildObjectMenuItems(object),
      handle: handle,
      onSecondaryTapDown: _secondaryTapHandler(object),
      child: child,
    );
  }

  bool _dismissActiveContextMenu() {
    return DesktopContextMenuRegistry.dismiss(_objectContextMenuGroup);
  }

  void _runMenuAction(VoidCallback action) {
    DesktopContextMenuRegistry.dismiss(_objectContextMenuGroup);
    action();
  }

  void _openObject(ObjectInfo object) {
    if (_isParentDirectory(object)) {
      onNavigateUp();
      return;
    }
    if (object.isDir) {
      onOpenDirectory(object.key);
      return;
    }
    onOpenFile(object);
  }

  bool _isSelected(ObjectInfo object) {
    if (_isParentDirectory(object)) {
      return false;
    }
    return selectedKeys.contains(object.key);
  }

  bool _isDeleting(ObjectInfo object) {
    if (_isParentDirectory(object)) {
      return false;
    }
    return deletingKeys.contains(object.key);
  }

  bool _showsSelectionControl(ObjectInfo object) {
    return !_isParentDirectory(object);
  }

  bool _shouldToggleSelectionOnClick(ObjectInfo object) {
    return selectedKeys.isNotEmpty && _showsSelectionControl(object);
  }

  bool _isParentDirectory(ObjectInfo object) {
    return object.key == FileManagerObjectBrowser._parentDirectoryEntry.key;
  }

  Widget _selectionTarget(ObjectInfo object, Widget child) {
    if (_isParentDirectory(object) || _isDeleting(object)) {
      return child;
    }
    return FileManagerDragSelectionTarget(
      selectionKey: object.key,
      enabled: true,
      child: child,
    );
  }
}
