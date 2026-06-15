// Desktop preview windows use a separate Flutter engine for roomy image viewing.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/models/file_preview_window_args.dart';

class FilePreviewWindowService {
  FilePreviewWindowService._();

  static final FilePreviewWindowService instance = FilePreviewWindowService._();

  bool get isSupported => true;

  Future<bool> openImagePreview({
    required String title,
    required String localPath,
  }) async {
    final args = FilePreviewWindowArgs(
      title: title,
      kind: FilePreviewKind.image,
      localPath: localPath,
    );
    await WindowController.create(
      WindowConfiguration(arguments: args.toArguments()),
    );
    return true;
  }
}
