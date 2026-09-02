// ignore_for_file: invalid_use_of_protected_member

part of 'file_manager_page.dart';

// 文件管理页多选逻辑：维护选中集合，并处理批量下载与批量删除。

extension _FileManagerPageSelection on _FileManagerPageState {
  List<ObjectInfo> get _visibleSelectableObjects {
    return filterVisibleObjects(
      _objects ?? const <ObjectInfo>[],
      hideDotFiles: _activeConfig.hideDotFiles,
    );
  }

  List<ObjectInfo> get _selectedObjects {
    return (_objects ?? const <ObjectInfo>[])
        .where((object) => _selectedObjectKeys.contains(object.key))
        .toList();
  }

  void _toggleObjectSelection(ObjectInfo object) {
    setState(() {
      if (!_selectedObjectKeys.add(object.key)) {
        _selectedObjectKeys.remove(object.key);
      }
    });
  }

  void _replaceSelectedObjects(Set<String> keys) {
    final visibleKeys = _filteredVisibleObjects
        .map((object) => object.key)
        .toSet();
    final normalized = keys.where(visibleKeys.contains).toSet();
    if (_selectedObjectKeys.length == normalized.length &&
        _selectedObjectKeys.containsAll(normalized)) {
      return;
    }
    setState(() {
      _selectedObjectKeys
        ..clear()
        ..addAll(normalized);
    });
  }

  void _selectObjectsForContextMenu(ObjectInfo object) {
    if (_selectedObjectKeys.contains(object.key)) {
      return;
    }
    setState(() {
      _selectedObjectKeys
        ..clear()
        ..add(object.key);
    });
  }

  void _clearSelection() {
    if (_selectedObjectKeys.isEmpty) {
      return;
    }
    setState(_selectedObjectKeys.clear);
  }

  void _toggleSelectAllObjects() {
    final selectableKeys = _filteredVisibleObjects
        .map((object) => object.key)
        .toSet();
    if (selectableKeys.isEmpty) {
      return;
    }

    final hasUnselected = selectableKeys.any(
      (key) => !_selectedObjectKeys.contains(key),
    );

    setState(() {
      if (hasUnselected) {
        _selectedObjectKeys.addAll(selectableKeys);
      } else {
        _selectedObjectKeys.removeAll(selectableKeys);
      }
    });
  }

  Future<void> _downloadSelectedObjects() async {
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) return;
    final config = bucketEntry.config;
    final bucket = bucketEntry.bucket.name;
    final prefix = _prefix;
    final sourceListingViewGeneration = _listingViewGeneration;
    final mobileRequest = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
    );
    bool isCurrentDownloadCommand() => _isCurrentObjectMutationCommand(
      bucketEntry,
      prefix,
      sourceListingViewGeneration,
      mobileRequest,
    );
    if (!isCurrentDownloadCommand()) return;
    final selected = _selectedObjects;
    if (selected.isEmpty) {
      return;
    }
    // Browser transfers and mobile clients without recursive directory
    // support must not enqueue a directory after a mixed selection. Keeping
    // the eligible set here makes the action-sheet affordance and executor
    // agree instead of silently attempting an unsupported transfer.
    final downloadable = widget.api.capabilities.supportsBrowserTransfers
        ? selected.where((object) => !object.isDir).toList(growable: false)
        : selected
              .where(
                (object) =>
                    !object.isDir ||
                    widget.api.capabilities.supportsDownloadDirectory,
              )
              .toList(growable: false);
    if (downloadable.isEmpty) {
      return;
    }
    if (widget.api.capabilities.supportsBrowserTransfers) {
      try {
        final requests = <FileAccessTransferRequest>[];
        final directoryLister = _downloadDirectoryLister(
          bucketEntry: bucketEntry,
          mobileRequest: mobileRequest,
          listingViewGeneration: sourceListingViewGeneration,
          requestStillCurrent: isCurrentDownloadCommand,
        );
        for (final object in downloadable) {
          if (!isCurrentDownloadCommand()) return;
          final request = await FileAccessService.instance
              .prepareDownloadObjectToPath(
                api: widget.api,
                config: config,
                bucket: bucket,
                object: object,
                savePath: object.displayName,
                directoryLister: directoryLister,
                canStartDownload: isCurrentDownloadCommand,
              );
          requests.add(request);
          // Attach the completion observer immediately. If a later selected
          // item loses the source-generation race, earlier requests may still
          // finish in the background and must not become unhandled futures.
          _watchDownloadRequest(request);
          if (!isCurrentDownloadCommand()) return;
        }
        if (!isCurrentDownloadCommand()) return;
        _clearSelection();
        await _showDownloadProgressDialogForTasks(_tasksForRequests(requests));
      } catch (error) {
        if (!mounted || !isCurrentDownloadCommand()) {
          return;
        }
        _showPageError(error);
      }
      return;
    }
    final targetDirectory = await resolveDefaultDownloadDirectory(
      config.defaultDownloadDirectory,
    );
    if (!isCurrentDownloadCommand()) return;
    if (targetDirectory == null || targetDirectory.isEmpty) {
      if (!mounted || !isCurrentDownloadCommand()) {
        return;
      }
      _showPageMessage(title: '下载失败', message: '无法确定默认下载目录');
      return;
    }

    try {
      final requests = <FileAccessTransferRequest>[];
      final directoryLister = _downloadDirectoryLister(
        bucketEntry: bucketEntry,
        mobileRequest: mobileRequest,
        listingViewGeneration: sourceListingViewGeneration,
        requestStillCurrent: isCurrentDownloadCommand,
      );
      for (final object in downloadable) {
        if (!isCurrentDownloadCommand()) return;
        final request = await FileAccessService.instance
            .prepareDownloadObjectToPath(
              api: widget.api,
              config: config,
              bucket: bucket,
              object: object,
              savePath: path.join(targetDirectory, object.displayName),
              directoryLister: directoryLister,
              canStartDownload: isCurrentDownloadCommand,
            );
        requests.add(request);
        _watchDownloadRequest(request);
        if (!isCurrentDownloadCommand()) return;
      }
      if (!isCurrentDownloadCommand()) return;
      _clearSelection();
      await _showDownloadProgressDialogForTasks(_tasksForRequests(requests));
    } catch (error) {
      if (!mounted || !isCurrentDownloadCommand()) {
        return;
      }
      _showPageError(error);
    }
  }

  Future<void> _deleteSelectedObjects() async {
    if (!mounted || _activeBucket == null || _selectedObjectKeys.isEmpty) {
      return;
    }
    if (!_currentDirectoryWritable) {
      _ensureCurrentDirectoryWritable();
      return;
    }
    final bucketEntry = _activeBucketEntry;
    if (bucketEntry == null) return;
    final prefix = _prefix;
    final sourceListingViewGeneration = _listingViewGeneration;
    final request = _captureMobileFileManagerRequest(
      _MobileFileManagerLocation.objects(bucketEntry, prefix),
    );
    if (!_isCurrentObjectMutationCommand(
      bucketEntry,
      prefix,
      sourceListingViewGeneration,
      request,
    )) {
      return;
    }
    final selected = _selectedObjects;
    final choice = await showDeleteObjectsDialog(
      context,
      selected.length,
      trashEnabled: _activeBucketTrashEnabled,
    );
    if (!choice.confirmed) {
      return;
    }
    // The selection dialog may stay open while Android replaces the bucket
    // entry during a bootstrap refresh. Do not let the current-state queue
    // turn this old selection into a write through the previous config.
    if (!_isCurrentObjectMutationCommand(
      bucketEntry,
      prefix,
      sourceListingViewGeneration,
      request,
    )) {
      return;
    }
    final tasks = _queueObjectDeletes(selected, permanent: choice.permanent);
    await _showDeleteProgressDialogForTasks(tasks);
  }
}
