// FFI bridge loading stays isolated so page code can remain Dart-first.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

typedef _NativeInvoke = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _DartInvoke = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _NativeFree = Void Function(Pointer<Utf8>);
typedef _DartFree = void Function(Pointer<Utf8>);

class RemoteStorageBridgeException implements Exception {
  const RemoteStorageBridgeException(this.message);

  final String message;

  @override
  String toString() => 'RemoteStorageBridgeException: $message';
}

class RemoteStorageBridge {
  RemoteStorageBridge._(DynamicLibrary library, this._libraryPath)
    : _invoke = library.lookupFunction<_NativeInvoke, _DartInvoke>(
        'RemoteStorageInvoke',
      ),
      _free = library.lookupFunction<_NativeFree, _DartFree>(
        'RemoteStorageFreeString',
      );

  final String _libraryPath;
  final _DartInvoke _invoke;
  final _DartFree _free;

  String get libraryPath => _libraryPath;

  static RemoteStorageBridge openAtPath(String libraryPath) {
    return RemoteStorageBridge._(DynamicLibrary.open(libraryPath), libraryPath);
  }

  static Future<RemoteStorageBridge> connect() async {
    final bundledLibraryPath = _findBundledLibraryPath();
    if (bundledLibraryPath != null) {
      final library = DynamicLibrary.open(bundledLibraryPath);
      return RemoteStorageBridge._(library, bundledLibraryPath);
    }

    final repoRoot = _locateRepoRoot();
    final outputPath = path.join(
      repoRoot.path,
      'bin',
      'bridge',
      _libraryFileName(),
    );
    final libraryFile = File(outputPath);
    if (!await libraryFile.exists()) {
      await _buildBridge(repoRoot, outputPath);
    }

    final library = DynamicLibrary.open(outputPath);
    return RemoteStorageBridge._(library, outputPath);
  }

  dynamic call(String method, [Object? args]) {
    final methodPtr = method.toNativeUtf8();
    final argsPtr = jsonEncode(
      args ?? const <String, dynamic>{},
    ).toNativeUtf8();

    try {
      final responsePtr = _invoke(methodPtr, argsPtr);
      try {
        final responseText = responsePtr.toDartString();
        final payload = jsonDecode(responseText) as Map<String, dynamic>;
        if (payload['ok'] != true) {
          final error =
              payload['error'] as Map<String, dynamic>? ??
              const <String, dynamic>{};
          throw RemoteStorageBridgeException(
            error['message']?.toString() ?? 'Bridge call failed.',
          );
        }
        return payload['result'];
      } finally {
        _free(responsePtr);
      }
    } finally {
      malloc.free(methodPtr);
      malloc.free(argsPtr);
    }
  }

  static Directory _locateRepoRoot() {
    final candidates = <Directory>[
      Directory.current.absolute,
      File(Platform.resolvedExecutable).absolute.parent,
    ];
    final scriptUri = Uri.tryParse(Platform.script.toString());
    if (scriptUri != null && scriptUri.scheme == 'file') {
      candidates.add(File(scriptUri.toFilePath()).absolute.parent);
    }

    for (final candidate in candidates) {
      final found = _searchRepoRoot(candidate);
      if (found != null) {
        return found;
      }
    }
    throw const RemoteStorageBridgeException(
      'Could not locate the Remote Storage repository root.',
    );
  }

  static String? _findBundledLibraryPath() {
    final libraryName = _libraryFileName();
    final executableDir = File(Platform.resolvedExecutable).absolute.parent;
    final candidates = <String>[
      path.join(executableDir.path, libraryName),
      if (Platform.isLinux) path.join(executableDir.path, 'lib', libraryName),
      if (Platform.isMacOS)
        path.normalize(
          path.join(executableDir.path, '..', 'Frameworks', libraryName),
        ),
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static Directory? _searchRepoRoot(Directory start) {
    var current = start.absolute;
    while (true) {
      final hasGoModule = File(path.join(current.path, 'go.mod')).existsSync();
      final hasBridgeDir = Directory(
        path.join(current.path, 'bridge'),
      ).existsSync();
      if (hasGoModule && hasBridgeDir) {
        return current;
      }

      final parent = current.parent;
      if (parent.path == current.path) {
        return null;
      }
      current = parent;
    }
  }

  static String _libraryFileName() {
    if (Platform.isMacOS) {
      return 'libremote_storage_bridge.dylib';
    }
    if (Platform.isWindows) {
      return 'remote_storage_bridge.dll';
    }
    return 'libremote_storage_bridge.so';
  }

  static Future<void> _buildBridge(
    Directory repoRoot,
    String outputPath,
  ) async {
    await Directory(path.dirname(outputPath)).create(recursive: true);
    final result = await Process.run('go', <String>[
      'build',
      '-buildmode=c-shared',
      '-o',
      outputPath,
      './bridge',
    ], workingDirectory: repoRoot.path);
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      throw RemoteStorageBridgeException(
        'Go bridge build failed.\n${stderr.isNotEmpty ? stderr : stdout}',
      );
    }
  }
}
