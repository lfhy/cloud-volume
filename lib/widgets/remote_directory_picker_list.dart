part of 'remote_directory_picker_dialog.dart';

// 目录浏览列表：目录可进入，文件仅展示（灰色不可点）；可选显示以 . 开头的隐藏文件。

extension _RemoteDirectoryPickerList on _RemoteDirectoryPickerDialogState {
  /// 多色 SVG（如 zip）用亮度矩阵去色，避免 srcATop 只染透明区、彩色图标不变灰。
  static const _fileIconGreyscale = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  static const _parentEntry = ObjectInfo(
    key: '../',
    size: 0,
    lastModified: '',
    isDir: true,
  );

  bool _isHiddenFileName(String name) {
    if (name == '..' || name.isEmpty) return false;
    return name.startsWith('.');
  }

  List<ObjectInfo> _directoryListItems() {
    var dirs = _objects.where((o) => o.isDir).toList();
    var files = _objects.where((o) => !o.isDir).toList();
    if (!_showHiddenFiles) {
      dirs = dirs.where((o) => !_isHiddenFileName(o.displayName)).toList();
      files = files.where((o) => !_isHiddenFileName(o.displayName)).toList();
    }
    files.sort((a, b) => a.displayName.compareTo(b.displayName));
    return [if (_prefix.isNotEmpty) _parentEntry, ...dirs, ...files];
  }

  Widget buildDirectoryList(ShadThemeData theme) {
    final items = _directoryListItems();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.folderOpen,
              size: 40,
              color: theme.colorScheme.mutedForeground.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 10),
            Text(
              '此目录为空',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => _objectEntryTile(theme, items[i]),
    );
  }

  Widget buildHiddenFilesToggle(ShadThemeData theme) {
    if (_activeBucket == null) return const SizedBox.shrink();
    return Row(
      children: [
        Text(
          '显示隐藏文件',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(width: 8),
        ShadSwitch(
          value: _showHiddenFiles,
          onChanged: (v) => markDirty(() => _showHiddenFiles = v),
        ),
      ],
    );
  }

  Widget _objectEntryTile(ShadThemeData theme, ObjectInfo obj) {
    final isParent = obj.key == '../';
    if (isParent) {
      return _dirTile(theme, obj);
    }
    if (obj.isDir) {
      return _dirTile(theme, obj);
    }
    return _fileTile(theme, obj);
  }

  Widget _fileTile(ShadThemeData theme, ObjectInfo obj) {
    final name = obj.displayName;
    return _RemoteDirectoryPickerListTile(
      leading: IgnorePointer(
        child: Opacity(
          opacity: 0.72,
          child: ColorFiltered(
            colorFilter: _fileIconGreyscale,
            child: LocalCloudPanFileIcon(
              name: name,
              isDirectory: false,
              size: 20,
            ),
          ),
        ),
      ),
      title: name,
      metadataLabel: obj.sizeText,
      dimmed: true,
      onTap: () {},
    );
  }
}

const double _remoteDirectoryPickerCompactRowWidth = 560;

/// Picker rows switch locally so shared file-list column alignment is unchanged.
class _RemoteDirectoryPickerListTile extends StatelessWidget {
  const _RemoteDirectoryPickerListTile({
    required this.leading,
    required this.title,
    required this.onTap,
    this.metadataLabel = '',
    this.dimmed = false,
  });

  final Widget leading;
  final String title;
  final String metadataLabel;
  final VoidCallback onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FileListTile(
          leading: leading,
          title: title,
          sizeLabel: metadataLabel,
          onTap: onTap,
          showDivider: false,
          dimmed: dimmed,
          compact: constraints.maxWidth < _remoteDirectoryPickerCompactRowWidth,
        );
      },
    );
  }
}
