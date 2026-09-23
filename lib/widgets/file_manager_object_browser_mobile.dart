part of 'file_manager_object_browser.dart';

// Android object rows mirror the compact bucket surface while keeping the
// desktop table, selection model, and mutation callbacks shared. Rows follow
// the two-state selection model: browse state shows a quiet trailing select
// dot (row tap opens, long-press selects); selection state shows the leading
// check control and row taps toggle selection. Row-level actions live in the
// page's selection bottom bar, not in per-row drawers.

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
    final canSelect = !parent && !deleting;
    final selectionActive = selectedKeys.isNotEmpty;
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
        // 浏览态行点击是主操作(_tapHandler 在无选择时打开对象),长按与
        // 行尾圆点进入选中态;选中态行点击切换选中。
        onTap: _tapHandler(object),
        onLongPress: canSelect
            ? () => onToggleSelection(object)
            : null,
        onDoubleTap: null,
        onTitleTap: _titleTapHandler(object),
        onSelectionTap: _selectionTapHandler(object),
        isSelected: _isSelected(object),
        showSelectionControl: selectionActive && _showsSelectionControl(object),
        showDivider: index != objectCount - 1 || loadingMore,
        deleting: deleting,
        compact: true,
        trailing: !selectionActive && canSelect
            ? MobileRowSelectDot(onTap: () => onToggleSelection(object))
            : null,
      ),
    );
  }
}
