// Web file-transfer fallback keeps local native clipboard paths disabled.

class DesktopFileTransferService {
  DesktopFileTransferService._();

  static final DesktopFileTransferService instance =
      DesktopFileTransferService._();

  static bool get supportsNativeFileClipboard => false;

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
