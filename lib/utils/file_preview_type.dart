// Preview type helpers keep extension matching out of file-manager widgets.

import 'package:path/path.dart' as path;
import 'package:remote_storage/models/file_preview_source.dart';

const Set<String> _imageExtensions = {
  '.apng',
  '.bmp',
  '.gif',
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
};

const Set<String> _videoExtensions = {
  '.avi',
  '.m4v',
  '.mkv',
  '.mov',
  '.mp4',
  '.webm',
};

const Set<String> _wordExtensions = {'.doc', '.docx', '.rtf'};

FilePreviewKind previewKindForName(String name) {
  final extension = path.extension(name).toLowerCase();
  if (_imageExtensions.contains(extension)) {
    return FilePreviewKind.image;
  }
  if (_videoExtensions.contains(extension)) {
    return FilePreviewKind.video;
  }
  if (extension == '.pdf') {
    return FilePreviewKind.pdf;
  }
  if (_wordExtensions.contains(extension)) {
    return FilePreviewKind.word;
  }
  return FilePreviewKind.unsupported;
}

String previewKindLabel(FilePreviewKind kind) {
  return switch (kind) {
    FilePreviewKind.image => '图片预览',
    FilePreviewKind.video => '视频预览',
    FilePreviewKind.pdf => 'PDF 预览',
    FilePreviewKind.word => 'Word 预览',
    FilePreviewKind.unsupported => '不支持预览',
  };
}
