part of 'cloud_storage_account_dialog.dart';

// Protocol-specific connection fields are split from wizard layout/chrome.
// They share the parent library's private account-draft state.

// ---------------------------------------------------------------------------
// Protocol-specific field builders (called from stepConnectionFields)
// ---------------------------------------------------------------------------

/// S3 fields: endpoint, region, access key, secret key.
List<Widget> _s3Fields(_CloudStorageAccountDialogState self) {
  return [
    CloudStorageLabeledField(
      label: '网关地址',
      child: CloudStorageTechnicalInput(
        controller: self._endpointController,
        keyboardType: TextInputType.url,
        placeholder: const Text('https://s3.example.com'),
      ),
    ),
    const SizedBox(height: 14),
    _twoColumnRow(
      left: CloudStorageLabeledField(
        label: '区域',
        child: CloudStorageTechnicalInput(
          controller: self._regionController,
          placeholder: const Text('Region，例如 auto'),
        ),
      ),
      right: CloudStorageLabeledField(
        label: '访问密钥 ID',
        child: CloudStorageTechnicalInput(
          controller: self._accessKeyController,
          placeholder: const Text('Access Key ID'),
          onChanged: (_) => self._onCredentialInputChanged(),
        ),
      ),
    ),
    const SizedBox(height: 14),
    CloudStorageLabeledField(
      label: '访问密钥',
      child: CloudStorageSecretInput(
        controller: self._secretKeyController,
        onChanged: (_) => self._onCredentialInputChanged(),
        placeholder: Text(
          self.widget.editing ? '留空则保留当前 Secret Key' : 'Secret Access Key',
        ),
      ),
    ),
    self._buildCredentialValidationControl(),
  ];
}

/// WebDAV fields: URL, username, password.
List<Widget> _webdavFields(_CloudStorageAccountDialogState self) {
  return [
    CloudStorageLabeledField(
      label: 'WebDAV 地址',
      child: CloudStorageTechnicalInput(
        controller: self._endpointController,
        keyboardType: TextInputType.url,
        placeholder: const Text(
          'https://dav.example.com/remote.php/dav/files/me',
        ),
      ),
    ),
    const SizedBox(height: 14),
    _twoColumnRow(
      left: CloudStorageLabeledField(
        label: '用户名',
        child: CloudStorageTechnicalInput(
          controller: self._webdavUsernameController,
          placeholder: const Text('输入 WebDAV 用户名'),
        ),
      ),
      right: CloudStorageLabeledField(
        label: '密码',
        child: CloudStorageSecretInput(
          controller: self._webdavPasswordController,
          placeholder: Text(
            self.widget.editing ? '留空则保留当前 WebDAV 密码' : '输入 WebDAV 登录密码',
          ),
        ),
      ),
    ),
  ];
}

/// FTP/SFTP fields: host, port, username, password, anonymous toggle.
List<Widget> _ftpFields(_CloudStorageAccountDialogState self) {
  final isSFTP = self._storageType == StorageType.sftp;
  final protocolLabel = isSFTP ? 'SFTP' : 'FTP';
  final defaultPort = isSFTP ? '22' : '21';
  return [
    _twoColumnRow(
      left: CloudStorageLabeledField(
        label: '$protocolLabel 地址',
        child: CloudStorageTechnicalInput(
          controller: self._endpointController,
          keyboardType: TextInputType.url,
          placeholder: Text('host 或 ${protocolLabel.toLowerCase()}://host'),
        ),
      ),
      right: CloudStorageLabeledField(
        label: '端口',
        child: CloudStorageTechnicalInput(
          controller: self._ftpPortController,
          keyboardType: TextInputType.number,
          placeholder: Text('默认 $defaultPort'),
        ),
      ),
    ),
    const SizedBox(height: 14),
    if (!self._ftpAnonymous)
      _twoColumnRow(
        left: CloudStorageLabeledField(
          label: '用户名',
          child: CloudStorageTechnicalInput(
            controller: self._ftpUsernameController,
            placeholder: Text('输入 $protocolLabel 用户名'),
          ),
        ),
        right: CloudStorageLabeledField(
          label: '密码',
          child: CloudStorageSecretInput(
            controller: self._ftpPasswordController,
            placeholder: Text(
              self.widget.editing ? '留空则保留当前密码' : '输入 $protocolLabel 登录密码',
            ),
          ),
        ),
      ),
    const SizedBox(height: 14),
    _ftpAnonymousToggle(self, protocolLabel),
  ];
}

/// Anonymous login toggle for FTP/SFTP.
class _FtpAnonymousToggle extends StatefulWidget {
  const _FtpAnonymousToggle({
    required _CloudStorageAccountDialogState self,
    required String protocolLabel,
  }) : _self = self,
       _protocolLabel = protocolLabel;

  final _CloudStorageAccountDialogState _self;
  final String _protocolLabel;

  @override
  State<_FtpAnonymousToggle> createState() => _FtpAnonymousToggleState();
}

class _FtpAnonymousToggleState extends State<_FtpAnonymousToggle> {
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ShadSwitch(
        value: widget._self._ftpAnonymous,
        onChanged: (value) => widget._self.markDirty(() {
          widget._self._ftpAnonymous = value;
        }),
        label: Text(
          '匿名登录',
          style: theme.textTheme.small.copyWith(
            color: theme.colorScheme.foreground,
            fontWeight: FontWeight.w500,
          ),
        ),
        sublabel: Text(
          '使用 anonymous 账号登录${widget._protocolLabel}服务器，无需用户名密码。',
          style: TextStyle(
            color: theme.colorScheme.mutedForeground,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

Widget _ftpAnonymousToggle(
  _CloudStorageAccountDialogState self,
  String protocolLabel,
) {
  return _FtpAnonymousToggle(self: self, protocolLabel: protocolLabel);
}

/// Baidu Pan fields: OAuth authorization section.
List<Widget> _baiduPanFields(_CloudStorageAccountDialogState self) {
  final label =
      self._authorizedBaiduConfig?.displayName.trim().isNotEmpty == true
      ? self._authorizedBaiduConfig!.displayName
      : self._nameController.text.trim();
  return [
    BaiduPanAuthSection(
      accountLabel: label,
      authorized:
          self._authorizedBaiduConfig?.accessKeyId.trim().isNotEmpty == true &&
          self._authorizedBaiduConfig?.hasSecretAccessKey == true,
      codeController: self._baiduAuthCodeController,
      authUrl: self._baiduAuthUrl,
      openingBrowser: self._openingBaiduAuthPage,
      submittingCode: self._authorizingBaidu,
      onOpenAuthorizationPage: self._startBaiduPanAuthorization,
      onSubmitAuthorizationCode: self._authorizeBaiduPan,
      errorText: self._baiduAuthErrorText,
    ),
  ];
}
