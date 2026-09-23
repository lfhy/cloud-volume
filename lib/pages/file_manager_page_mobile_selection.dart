// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// Android 两态选择模型(文件管理页):浏览态行尾选择圆点、选中态头部变形
// (取消/已选中 N 个/全选)+ 底部动作条。对象视图复用 _selectedObjectKeys;
// 桶内回收站视图用独立的 _selectedTrashItemIds,并提供单选等价的批量
// 恢复/彻底删除。行级动作不再放进每行 `…` 抽屉。

extension _FileManagerPageMobileSelection on _FileManagerPageState {
  /// 当前选中态是否激活(移动端)。对象视图看对象选择,桶内回收站视图看
  /// 回收站选择;桶列表不可选。
  bool get _mobileSelectionActive =>
      _usesMobileNavigation &&
      (_showTrash
          ? _selectedTrashItemIds.isNotEmpty
          : _selectedObjectKeys.isNotEmpty);

  int get _mobileSelectionCount => _showTrash
      ? _selectedTrashItemIds.length
      : _selectedObjectKeys.length;

  /// 选中态头部;浏览态返回 null(调用方回落到常规移动头部)。
  Widget? _buildMobileSelectionHeader() {
    if (!_mobileSelectionActive) return null;
    if (_showTrash) {
      final selectableIds = _filteredTrashItems
          .map((item) => item.id)
          .toSet();
      final allSelected =
          selectableIds.isNotEmpty &&
          selectableIds.every(_selectedTrashItemIds.contains);
      return MobileSelectionHeader(
        count: _mobileSelectionCount,
        noun: '文件',
        allSelected: allSelected,
        onCancel: _clearMobileSelection,
        onToggleSelectAll: _toggleSelectAllTrashFiltered,
      );
    }
    final selectableKeys = _filteredVisibleObjects
        .map((object) => object.key)
        .toSet();
    final allSelected =
        selectableKeys.isNotEmpty &&
        selectableKeys.every(_selectedObjectKeys.contains);
    return MobileSelectionHeader(
      count: _mobileSelectionCount,
      noun: '项',
      allSelected: allSelected,
      onCancel: _clearMobileSelection,
      onToggleSelectAll: _toggleSelectAllObjects,
    );
  }

  void _clearMobileSelection() {
    if (!_mobileSelectionActive) return;
    setState(() {
      _selectedObjectKeys.clear();
      _selectedTrashItemIds.clear();
    });
  }

  /// 系统 Back 在选中态先清空选择,再走正常的位置回退。
  bool _consumeMobileSelectionForBack() {
    if (!_mobileSelectionActive) return false;
    _clearMobileSelection();
    return true;
  }

  /// 选中态底部动作条(百度式两排全量动作,全宽贴底);浏览态返回空盒。
  Widget _buildMobileSelectionBar() {
    if (!_usesMobileNavigation || !_mobileSelectionActive) {
      return const SizedBox.shrink();
    }
    final actions = _showTrash
        ? _mobileTrashSelectionActions()
        : _mobileObjectSelectionActions();
    return MobileSelectionBottomBar(actions: actions);
  }

  List<MobilePageAction> _mobileObjectSelectionActions() {
    final selected = _selectedObjects;
    if (selected.isEmpty) return const <MobilePageAction>[];
    final readOnly = !_currentDirectoryWritable;
    if (selected.length == 1) {
      final object = selected.single;
      final bucketLabel = _presentationBucketEntry?.label ?? '';
      return <MobilePageAction>[
        // 详情(文件详情 sheet)是首项:纯信息无动作,展示列表已有的
        // 名称/大小/时间与完整路径、所属桶。
        MobilePageAction(
          label: '详情',
          icon: LucideIcons.info,
          onPressed: () => unawaited(
            showMobileDetailSheet(
              context,
              title: '文件详情',
              rows: [
                MobileDetailRow('名称', object.displayName),
                MobileDetailRow('类型', object.isDir ? '文件夹' : '文件'),
                if (object.sizeText.isNotEmpty)
                  MobileDetailRow('大小', object.sizeText),
                if (object.lastModified.isNotEmpty)
                  MobileDetailRow('修改时间', object.lastModified),
                MobileDetailRow('完整路径', object.key),
                if (bucketLabel.isNotEmpty)
                  MobileDetailRow('所属桶', bucketLabel),
              ],
            ),
          ),
        ),
        MobilePageAction(
          label: object.isDir ? '打开' : '预览',
          icon: object.isDir ? LucideIcons.folderOpen : LucideIcons.eye,
          onPressed: () => unawaited(_openObject(object)),
        ),
        if (!object.isDir || supportsDirectoryDownloadFor(object))
          MobilePageAction(
            label: '下载',
            icon: LucideIcons.download,
            onPressed: () => unawaited(_downloadObject(object)),
          ),
        if (_activeConfig.supportsShareLinks && !object.isDir)
          MobilePageAction(
            label: '创建分享',
            icon: LucideIcons.share2,
            onPressed: () => unawaited(
              _handleObjectAction(object, FileObjectAction.share),
            ),
          ),
        if (!readOnly) ..._mobileObjectWriteActions(object),
      ];
    }
    return <MobilePageAction>[
      if (_canDownloadSelectedMobileObjects)
        MobilePageAction(
          label: '下载',
          icon: LucideIcons.download,
          onPressed: () => unawaited(
            _handleSelectedObjectsAction(FileSelectionAction.download),
          ),
        ),
      if (!readOnly) ...[
        MobilePageAction(
          label: '复制',
          icon: LucideIcons.copy,
          onPressed: () => unawaited(
            _handleSelectedObjectsAction(FileSelectionAction.copy),
          ),
        ),
        MobilePageAction(
          label: '移动',
          icon: LucideIcons.move,
          onPressed: () => unawaited(
            _handleSelectedObjectsAction(FileSelectionAction.move),
          ),
        ),
        MobilePageAction(
          label: '删除',
          icon: LucideIcons.trash2,
          onPressed: () => unawaited(
            _handleSelectedObjectsAction(FileSelectionAction.delete),
          ),
        ),
      ],
    ];
  }

  List<MobilePageAction> _mobileObjectWriteActions(ObjectInfo object) {
    return <MobilePageAction>[
      MobilePageAction(
        label: '复制到...',
        icon: LucideIcons.copy,
        onPressed: () => unawaited(
          _handleObjectAction(object, FileObjectAction.copy),
        ),
      ),
      MobilePageAction(
        label: '移动到...',
        icon: LucideIcons.move,
        onPressed: () => unawaited(
          _handleObjectAction(object, FileObjectAction.move),
        ),
      ),
      MobilePageAction(
        label: '重命名',
        icon: LucideIcons.pencil,
        onPressed: () => unawaited(
          _handleObjectAction(object, FileObjectAction.rename),
        ),
      ),
      MobilePageAction(
        label: '删除',
        icon: LucideIcons.trash2,
        onPressed: () => unawaited(
          _handleObjectAction(object, FileObjectAction.delete),
        ),
      ),
    ];
  }

  /// Directory downloads need either the native recursive lister or the
  /// browser-transfer flow; mirrors the object browser's row gating.
  bool supportsDirectoryDownloadFor(ObjectInfo object) {
    if (!object.isDir) return true;
    return widget.api.capabilities.supportsDownloadDirectory;
  }

  bool get _canDownloadSelectedMobileObjects {
    final selected = _selectedObjects;
    final hasFile = selected.any((object) => !object.isDir);
    if (hasFile) return true;
    return selected.any((object) => object.isDir) &&
        widget.api.capabilities.supportsDownloadDirectory &&
        !widget.api.capabilities.supportsBrowserTransfers;
  }

  List<MobilePageAction> _mobileTrashSelectionActions() {
    final selected = _filteredTrashItems
        .where((item) => _selectedTrashItemIds.contains(item.id))
        .toList(growable: false);
    if (selected.isEmpty) return const <MobilePageAction>[];
    if (selected.length == 1) {
      final item = selected.single;
      final bucketLabel = _presentationBucketEntry?.label ?? '';
      return <MobilePageAction>[
        MobilePageAction(
          label: '详情',
          icon: LucideIcons.info,
          onPressed: () => unawaited(
            showMobileDetailSheet(
              context,
              title: '文件详情',
              rows: [
                MobileDetailRow('名称', item.name),
                MobileDetailRow('类型', item.isDir ? '文件夹' : '文件'),
                if (item.sizeText.isNotEmpty)
                  MobileDetailRow('大小', item.sizeText),
                MobileDetailRow('删除时间', item.deletedAt),
                if (item.originalKey.isNotEmpty)
                  MobileDetailRow('原路径', item.originalKey),
                if (bucketLabel.isNotEmpty)
                  MobileDetailRow('所属桶', bucketLabel),
              ],
            ),
          ),
        ),
        MobilePageAction(
          label: '恢复',
          icon: LucideIcons.rotateCcw,
          onPressed: () => unawaited(_restoreTrashItem(item)),
        ),
        MobilePageAction(
          label: '彻底删除',
          icon: LucideIcons.trash2,
          onPressed: () => unawaited(_deleteTrashItemPermanently(item)),
        ),
      ];
    }
    return <MobilePageAction>[
      MobilePageAction(
        label: '恢复',
        icon: LucideIcons.rotateCcw,
        onPressed: () => unawaited(_restoreSelectedTrashItems()),
      ),
      MobilePageAction(
        label: '彻底删除',
        icon: LucideIcons.trash2,
        onPressed: () => unawaited(_deleteSelectedTrashItemsPermanently()),
      ),
    ];
  }

  void _toggleTrashItemSelection(TrashItem item) {
    setState(() {
      if (!_selectedTrashItemIds.remove(item.id)) {
        _selectedTrashItemIds.add(item.id);
      }
    });
  }

  void _toggleSelectAllTrashFiltered() {
    final selectableIds = _filteredTrashItems.map((item) => item.id).toSet();
    if (selectableIds.isEmpty) return;
    final hasUnselected = selectableIds.any(
      (id) => !_selectedTrashItemIds.contains(id),
    );
    setState(() {
      if (hasUnselected) {
        _selectedTrashItemIds.addAll(selectableIds);
      } else {
        _selectedTrashItemIds.removeAll(selectableIds);
      }
    });
  }

  /// 批量恢复桶内回收站:逐项调用 restore API 后统一 reload(与全局回收站
  /// 页的批量路径一致),复用单条路径的 request/generation 守卫。
  Future<void> _restoreSelectedTrashItems() async {
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) return;
    final targets = _filteredTrashItems
        .where((item) => _selectedTrashItemIds.contains(item.id))
        .toList(growable: false);
    if (targets.isEmpty) return;
    final sourceListingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.trash(bucketEntry),
    );
    if (!_isCurrentMobileFileManagerRequest(request)) return;
    setState(() {
      _loading = true;
      _error = null;
      _selectedTrashItemIds.clear();
    });
    try {
      for (final item in targets) {
        await widget.api.restoreTrashItem(
          bucketEntry.config,
          bucketEntry.bucket.name,
          item.id,
          originalKey: item.originalKey,
          isDirectory: item.isDir,
        );
      }
      _invalidateObjectListingCache(bucketId: bucketEntry.id);
      ObjectListingNotifier.instance.markRestored(
        bucketEntry.bucket.name,
        targets,
      );
      if (!_isCurrentTrashMutationSource(
        bucketEntry,
        sourceListingViewGeneration,
      )) {
        return;
      }
      final reloaded = await _reloadBucketTrashAfterMutation(bucketEntry);
      if (!reloaded) return;
      final currentRequest = _captureMobileFileManagerRequest(
        _MobileFileManagerLocation.trash(bucketEntry),
      );
      if (!_isCurrentMobileFileManagerRequest(currentRequest)) return;
      _showPageSnack('已恢复 ${targets.length} 个项目');
    } catch (error) {
      _invalidateObjectListingCache(bucketId: bucketEntry.id);
      final shouldReport =
          _isCurrentMobileFileManagerRequest(request) &&
          _isCurrentTrashMutationSource(
            bucketEntry,
            sourceListingViewGeneration,
          );
      if (shouldReport) {
        setState(() => _loading = false);
        _showPageError(error);
      }
      unawaited(
        _recoverTrashAfterUncertainMutation(
          bucketEntry,
          sourceListingViewGeneration,
        ),
      );
    }
  }

  Future<void> _deleteSelectedTrashItemsPermanently() async {
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) return;
    final targets = _filteredTrashItems
        .where((item) => _selectedTrashItemIds.contains(item.id))
        .toList(growable: false);
    if (targets.isEmpty) return;
    final sourceListingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.trash(bucketEntry),
    );
    if (!_isCurrentTrashMutationCommand(
      bucketEntry,
      sourceListingViewGeneration,
      request,
    )) {
      return;
    }
    final confirmed = await showDeleteTrashItemsDialog(context, targets.length);
    if (!confirmed ||
        !_isCurrentTrashMutationCommand(
          bucketEntry,
          sourceListingViewGeneration,
          request,
        )) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _selectedTrashItemIds.clear();
    });
    try {
      for (final item in targets) {
        await widget.api.deleteTrashItem(
          bucketEntry.config,
          bucketEntry.bucket.name,
          item.id,
        );
      }
      if (!_isCurrentTrashMutationCommand(
        bucketEntry,
        sourceListingViewGeneration,
        request,
      )) {
        return;
      }
      await _reloadBucketTrashAfterMutation(bucketEntry);
    } catch (error) {
      final shouldReport = _isCurrentTrashMutationCommand(
        bucketEntry,
        sourceListingViewGeneration,
        request,
      );
      if (shouldReport) {
        setState(() => _loading = false);
        _showPageError(error);
      }
      unawaited(
        _recoverTrashAfterUncertainMutation(
          bucketEntry,
          sourceListingViewGeneration,
        ),
      );
    }
  }
}
