part of 'config_setup_page.dart';

// First-run account validation and persistence stay separate from page layout.
extension _ConfigSetupSave on _ConfigSetupPageState {
  Future<void> _save() async {
    final isWebDav = _storageType == StorageType.webdav;
    final isBaiduPan = _storageType == StorageType.baiduPan;
    final isFTP =
        _storageType == StorageType.ftp || _storageType == StorageType.sftp;
    final name = _nameController.text.trim();
    final config = RemoteStorageConfig(
      endpoint: isBaiduPan
          ? (_authorizedBaiduConfig?.endpoint ?? _kBaiduPanEndpoint)
          : _endpointController.text,
      storageType: _storageType,
      providerType: isBaiduPan
          ? StorageProviderType.baiduPan
          : widget.initialState.config.providerType,
      displayName: name,
      mappedBucketName: isWebDav || isFTP
          ? (_mappedBucketNameController.text.trim().isNotEmpty
                ? _mappedBucketNameController.text
                : name)
          : isBaiduPan
          ? (name.isEmpty ? '百度网盘' : name)
          : name,
      region: _regionController.text,
      bucket: widget.initialState.config.bucket,
      accessKeyId: isBaiduPan
          ? (_authorizedBaiduConfig?.accessKeyId ?? '')
          : isWebDav || isFTP
          ? ''
          : _accessKeyController.text,
      secretAccessKey: isBaiduPan
          ? (_authorizedBaiduConfig?.secretAccessKey ?? '')
          : isWebDav || isFTP
          ? ''
          : _secretKeyController.text,
      hasSecretAccessKey: isBaiduPan
          ? (_authorizedBaiduConfig?.hasSecretAccessKey ?? false)
          : !isWebDav &&
                !isFTP &&
                widget.initialState.config.hasSecretAccessKey,
      webdavUsername: isWebDav
          ? _webdavUsernameController.text
          : isBaiduPan || isFTP
          ? ''
          : _accessKeyController.text,
      webdavPassword: isWebDav
          ? _webdavPasswordController.text
          : isBaiduPan || isFTP
          ? ''
          : _secretKeyController.text,
      hasWebdavPassword:
          isWebDav && widget.initialState.config.hasWebdavPassword,
      ftpUsername: isFTP ? _ftpUsernameController.text : '',
      ftpPassword: isFTP ? _ftpPasswordController.text : '',
      hasFtpPassword: isFTP && widget.initialState.config.hasFtpPassword,
      ftpPort: isFTP ? (int.tryParse(_ftpPortController.text.trim()) ?? 0) : 0,
      ftpAnonymous: false,
      rootPrefix: widget.initialState.config.rootPrefix,
      defaultDownloadDirectory:
          widget.initialState.config.defaultDownloadDirectory,
      cacheDirectory: widget.initialState.config.cacheDirectory,
      resolvedCacheDirectory: widget.initialState.config.resolvedCacheDirectory,
      hideDotFiles: widget.initialState.config.hideDotFiles,
      fileOpenMode: FileOpenMode.singleClick,
      trashDirectoryName: widget.initialState.config.trashDirectoryName,
      trashRetentionDays: widget.initialState.config.trashRetentionDays,
      bucketSettings: widget.initialState.config.bucketSettings,
      bucketViews: widget.initialState.config.bucketViews,
      writebackQuietSeconds: widget.initialState.config.writebackQuietSeconds,
      mountMetadataCacheSeconds:
          widget.initialState.config.mountMetadataCacheSeconds,
      mountRemotePollSeconds: widget.initialState.config.mountRemotePollSeconds,
      usePathStyle: _usePathStyle,
      windowsMountMode: widget.initialState.config.windowsMountMode,
      windowsMountEngine: widget.initialState.config.windowsMountEngine,
      windowsWinFspCapacityGb:
          widget.initialState.config.windowsWinFspCapacityGb,
      windowsThisPcEntryEnabled:
          widget.initialState.config.windowsThisPcEntryEnabled,
      windowsWritebackConcurrency:
          widget.initialState.config.windowsWritebackConcurrency,
      cacheAutoCleanupEnabled:
          widget.initialState.config.cacheAutoCleanupEnabled,
      cacheMaxSizeMb: widget.initialState.config.cacheMaxSizeMb,
      cacheMaxAgeDays: widget.initialState.config.cacheMaxAgeDays,
      jwanfsGatewayMode: _jwanfsGatewayMode,
      proxyMode: widget.initialState.config.proxyMode,
      proxyType: widget.initialState.config.proxyType,
      proxyHost: widget.initialState.config.proxyHost,
      proxyPort: widget.initialState.config.proxyPort,
      proxyUsername: widget.initialState.config.proxyUsername,
      proxyPassword: widget.initialState.config.proxyPassword,
    );

    if (!config.isConfigured) {
      _updateState(() {
        _errorText = isBaiduPan
            ? '请先完成百度网盘 OAuth 授权。'
            : isWebDav
            ? '请填写 WebDAV 地址、用户名和密码。'
            : '请填写 Endpoint、Access Key 和 Secret Key。';
      });
      return;
    }

    _updateState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await widget.api.saveConfig(config);
      if (!mounted) return;
      widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      _updateState(() {
        _errorText = describeBridgeError(error);
      });
    } finally {
      if (mounted) {
        _updateState(() {
          _isSaving = false;
        });
      }
    }
  }
}
