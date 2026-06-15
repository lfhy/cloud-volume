// Preview type tests lock down the default click-to-preview routing.

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/utils/file_preview_type.dart';

void main() {
  test('previewKindForName recognizes common preview candidates', () {
    expect(previewKindForName('photo.JPG'), FilePreviewKind.image);
    expect(previewKindForName('movie.mp4'), FilePreviewKind.video);
    expect(previewKindForName('paper.pdf'), FilePreviewKind.pdf);
    expect(previewKindForName('doc.docx'), FilePreviewKind.word);
    expect(previewKindForName('archive.zip'), FilePreviewKind.unsupported);
  });
}
