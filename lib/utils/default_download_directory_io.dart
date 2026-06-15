// Download directory helpers centralize the fallback logic for desktop saves.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> resolveDefaultDownloadDirectory(String configuredPath) async {
  final trimmed = configuredPath.trim();
  if (trimmed.isNotEmpty) {
    return trimmed;
  }

  try {
    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir == null) {
      return null;
    }
    await downloadsDir.create(recursive: true);
    return downloadsDir.path;
  } on UnsupportedError {
    return null;
  } on FileSystemException {
    return null;
  }
}
