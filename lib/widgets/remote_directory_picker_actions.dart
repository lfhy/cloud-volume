part of 'remote_directory_picker_dialog.dart';

// 远程目录选择器的数据加载与创建目录动作。

extension _RemoteDirectoryPickerActions on _RemoteDirectoryPickerDialogState {
  Future<void> _loadObjects() async {
    if (_activeBucket == null) return;
    final generation = ++_loadGeneration;
    final bucket = _activeBucket!;
    final prefix = _prefix;
    markDirty(() {
      _loading = true;
      _error = null;
    });
    try {
      final objects = await widget.api.listObjects(
        bucket.config,
        bucket.bucket.name,
        prefix,
      );
      if (!mounted || generation != _loadGeneration) return;
      markDirty(() {
        _objects = objects;
        _error = null;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      markDirty(() => _error = '加载失败：${describeBridgeError(e)}');
    } finally {
      if (mounted && generation == _loadGeneration) {
        markDirty(() => _loading = false);
      }
    }
  }

  Future<void> _createDirectory() async {
    final name = _dirNameController.text.trim();
    if (name.isEmpty || _activeBucket == null) return;
    try {
      await widget.api.createDirectory(
        _activeBucket!.config,
        _activeBucket!.bucket.name,
        _prefix,
        name,
      );
      if (!mounted) return;
      markDirty(() => _showCreateDir = false);
      _dirNameController.clear();
      showAppToast(context, message: '目录已创建');
      await _loadObjects();
    } catch (e) {
      if (!mounted) return;
      showAppErrorToast(context, message: '创建失败：$e');
    }
  }

  /// 创建目录的内联输入行，展开时显示在内容区上方。
  Widget buildCreateDirInput(ShadThemeData theme) {
    if (!_showCreateDir) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: _dirNameController,
              placeholder: const Text('输入目录名称'),
              autofocus: true,
              onSubmitted: (_) => _createDirectory(),
            ),
          ),
          const SizedBox(width: 8),
          ShadButton(onPressed: _createDirectory, child: const Text('创建')),
        ],
      ),
    );
  }

  /// Bottom actions stay in one desktop row and regroup vertically when the
  /// actual button widths no longer fit a phone-sized dialog.
  Widget _buildActions() {
    final navigationActions = <Widget>[
      if (_activeBucket != null) ...[
        ShadButton.outline(
          onPressed: _goBackToBuckets,
          child: const Row(
            children: [
              Icon(LucideIcons.chevronLeft, size: 14),
              SizedBox(width: 2),
              Text('桶列表'),
            ],
          ),
        ),
        ShadButton.outline(
          onPressed: _toggleCreateDir,
          child: const Row(
            children: [
              Icon(LucideIcons.folderPlus, size: 14),
              SizedBox(width: 2),
              Text('新建目录'),
            ],
          ),
        ),
      ],
    ];
    final confirmationActions = <Widget>[
      ShadButton.outline(onPressed: _cancel, child: const Text('取消')),
      ShadButton(
        onPressed: _activeBucket == null ? null : _confirm,
        child: const Text('选择当前目录'),
      ),
    ];
    return OverflowBar(
      spacing: 8,
      overflowSpacing: 8,
      alignment: navigationActions.isEmpty
          ? MainAxisAlignment.end
          : MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      children: [
        if (navigationActions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: navigationActions),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: confirmationActions,
        ),
      ],
    );
  }

  void _toggleCreateDir() {
    markDirty(() {
      _showCreateDir = !_showCreateDir;
      _dirNameController.clear();
    });
  }
}
