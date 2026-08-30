part of 'cloud_storage_account_dialog.dart';

// Baidu OAuth actions stay separate from the account dialog's layout/state
// assembly so the main widget remains within the repository size budget.
extension _CloudStorageAccountDialogOAuth on _CloudStorageAccountDialogState {
  Future<void> _authorizeBaiduPan() async {
    final code = _baiduAuthCodeController.text.trim();
    if (code.isEmpty) {
      markDirty(() => _baiduAuthErrorText = '请先粘贴百度授权页显示的授权码。');
      return;
    }
    markDirty(() {
      _authorizingBaidu = true;
      _baiduAuthErrorText = null;
    });
    try {
      final config = await widget.onAuthorizeBaiduPan(
        _nameController.text.trim(),
        code,
      );
      if (!mounted) return;
      markDirty(() {
        _authorizedBaiduConfig = config;
        _baiduAuthCodeController.clear();
        _baiduAuthErrorText = null;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = config.displayName;
        }
      });
      if (widget.editing || widget.simpleMode) {
        // Simple backup-only and editing flows have no visibility step.
        await _submit();
      } else {
        await _loadBucketsForVisibility();
      }
    } catch (error) {
      if (!mounted) return;
      markDirty(() => _baiduAuthErrorText = describeBridgeError(error));
    } finally {
      if (mounted) markDirty(() => _authorizingBaidu = false);
    }
  }

  Future<void> _startBaiduPanAuthorization() async {
    markDirty(() {
      _openingBaiduAuthPage = true;
      _baiduAuthErrorText = null;
    });
    try {
      final authUrl = await widget.onStartBaiduPanAuthorization();
      if (!mounted) return;
      markDirty(() => _baiduAuthUrl = authUrl);
    } catch (error) {
      if (!mounted) return;
      markDirty(() => _baiduAuthErrorText = describeBridgeError(error));
    } finally {
      if (mounted) markDirty(() => _openingBaiduAuthPage = false);
    }
  }
}
