// Web file-transfer fallback keeps desktop-only native clipboard paths disabled.

import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class DesktopFileTransferService {
  DesktopFileTransferService._();

  static final DesktopFileTransferService instance =
      DesktopFileTransferService._();

  Future<List<String>> localFilePathsFromDrop(PerformDropEvent event) async {
    return const <String>[];
  }

  Future<List<String>> localFilePathsFromClipboard() async {
    return const <String>[];
  }

  Future<List<LocalUploadEntry>> localUploadEntries(
    List<String> localPaths,
  ) async {
    return const <LocalUploadEntry>[];
  }

  Future<void> writeLocalFilesToClipboard(List<String> localPaths) async {}
}

class LocalUploadEntry {
  const LocalUploadEntry._({
    required this.localPath,
    required this.relativeKey,
    required this.isDirectory,
  });

  const LocalUploadEntry.file(String localPath, String relativeKey)
    : this._(
        localPath: localPath,
        relativeKey: relativeKey,
        isDirectory: false,
      );

  const LocalUploadEntry.directory(String localPath, String relativeKey)
    : this._(localPath: localPath, relativeKey: relativeKey, isDirectory: true);

  final String localPath;
  final String relativeKey;
  final bool isDirectory;
}
