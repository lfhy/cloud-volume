// Desktop file-transfer service bridges native drop/clipboard file URIs.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class DesktopFileTransferService {
  DesktopFileTransferService._();

  static final DesktopFileTransferService instance =
      DesktopFileTransferService._();

  Future<List<String>> localFilePathsFromDrop(PerformDropEvent event) async {
    final uris = await Future.wait(
      event.session.items.map((item) => _readFileUri(item.dataReader)),
    );
    return _existingFilePaths(uris);
  }

  Future<List<String>> localFilePathsFromClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return const <String>[];
    }
    final reader = await clipboard.read();
    final uris = <Uri>[];
    for (final item in reader.items) {
      if (!item.canProvide(Formats.fileUri)) {
        continue;
      }
      final uri = await item.readValue(Formats.fileUri);
      if (uri != null) {
        uris.add(uri);
      }
    }
    return _existingFilePaths(uris);
  }

  Future<List<LocalUploadEntry>> localUploadEntries(
    List<String> localPaths,
  ) async {
    final entries = <LocalUploadEntry>[];
    for (final localPath in localPaths) {
      if (FileSystemEntity.isFileSync(localPath)) {
        entries.add(LocalUploadEntry.file(localPath, path.basename(localPath)));
      } else if (FileSystemEntity.isDirectorySync(localPath)) {
        entries.add(
          LocalUploadEntry.directory(localPath, path.basename(localPath)),
        );
      }
    }
    return entries;
  }

  Future<void> writeLocalFilesToClipboard(List<String> localPaths) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null || localPaths.isEmpty) {
      return;
    }
    final items = localPaths
        .map((localPath) {
          final item = DataWriterItem(suggestedName: path.basename(localPath));
          item.add(Formats.fileUri(Uri.file(localPath)));
          return item;
        })
        .toList(growable: false);
    await clipboard.write(items);
  }

  Future<Uri?> _readFileUri(DataReader? reader) async {
    if (reader == null || !reader.canProvide(Formats.fileUri)) {
      return null;
    }
    final completer = Completer<Uri?>();
    reader.getValue<Uri>(
      Formats.fileUri,
      (value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
  }

  List<String> _existingFilePaths(Iterable<Uri?> uris) {
    final paths = <String>[];
    for (final uri in uris) {
      if (uri == null || !uri.isScheme('file')) {
        continue;
      }
      final localPath = uri.toFilePath();
      if (FileSystemEntity.isFileSync(localPath) ||
          FileSystemEntity.isDirectorySync(localPath)) {
        paths.add(localPath);
      }
    }
    return paths;
  }
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
