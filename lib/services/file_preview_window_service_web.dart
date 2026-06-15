// Web preview-window fallback reports unsupported so callers can keep dialogs.

class FilePreviewWindowService {
  FilePreviewWindowService._();

  static final FilePreviewWindowService instance = FilePreviewWindowService._();

  bool get isSupported => false;

  Future<bool> openImagePreview({
    required String title,
    required String localPath,
  }) async {
    return false;
  }
}
