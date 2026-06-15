// File preview source values are shared by desktop and web preview flows.

import 'dart:typed_data';

enum FilePreviewKind { image, video, pdf, word, unsupported }

class FilePreviewSource {
  const FilePreviewSource({this.bytes, this.uri});

  final Uint8List? bytes;
  final Uri? uri;

  bool get hasInlineData => bytes != null || uri != null;
}
