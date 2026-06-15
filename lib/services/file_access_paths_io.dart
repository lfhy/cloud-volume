// File access path helpers keep desktop download naming rules isolated.

import 'dart:io';

import 'package:path/path.dart' as path;

String uniqueDownloadPath(String directory, String fileName) {
  var candidate = path.join(directory, fileName);
  if (!File(candidate).existsSync()) {
    return candidate;
  }
  final extension = path.extension(fileName);
  final baseName = path.basenameWithoutExtension(fileName);
  for (var index = 1; index < 1000; index += 1) {
    candidate = path.join(directory, '$baseName ($index)$extension');
    if (!File(candidate).existsSync()) {
      return candidate;
    }
  }
  return path.join(
    directory,
    '$baseName-${DateTime.now().millisecondsSinceEpoch}$extension',
  );
}

String uniqueDownloadDirectoryPath(String directory, String name) {
  var candidate = path.join(directory, name);
  if (!Directory(candidate).existsSync() && !File(candidate).existsSync()) {
    return candidate;
  }
  for (var index = 1; index < 1000; index += 1) {
    candidate = path.join(directory, '$name ($index)');
    if (!Directory(candidate).existsSync() && !File(candidate).existsSync()) {
      return candidate;
    }
  }
  return path.join(directory, '$name-${DateTime.now().millisecondsSinceEpoch}');
}
