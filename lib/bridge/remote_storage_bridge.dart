// FFI bridge loading stays isolated so page code can remain Dart-first.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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
    if (Platform.isAndroid) {
      final bridge = RemoteStorageBridge._(
        DynamicLibrary.open('libremote_storage_bridge.so'),
        'libremote_storage_bridge.so',
      );
      final supportDirectory = await getApplicationSupportDirectory();
      bridge.call('set_app_data_root', <String, String>{
        'path': path.join(supportDirectory.path, 'cloud-volume'),
      });
      return bridge;
    }
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

  // Resolve the bundled Go bridge dylib.
  //
  // macOS app bundles may carry the dylib in two locations:
  //   - Contents/Frameworks/<dylib>  ← canonical, written by `make build-macos`
  //   - Contents/MacOS/<dylib>       ← stray copy from older Debug/Release runs
  // We probe Frameworks FIRST. Placing MacOS/ first would load a stale dylib
  // left over from a previous build whenever the Frameworks copy is updated,
  // causing "unsupported bridge method" errors for newly added methods like
  // install_app. Frameworks is the canonical Makefile target, so it wins.
  static String? _findBundledLibraryPath() {
    final libraryName = _libraryFileName();
    final executableDir = File(Platform.resolvedExecutable).absolute.parent;
    final candidates = <String>[
      if (Platform.isMacOS)
        path.normalize(
          path.join(executableDir.path, '..', 'Frameworks', libraryName),
        ),
      if (Platform.isLinux) path.join(executableDir.path, 'lib', libraryName),
      path.join(executableDir.path, libraryName),
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
      '-ldflags',
      '-X main.buildArch=${_hostGoArch()}',
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

  static String _hostGoArch() {
    if (Platform.version.contains('arm64') ||
        Platform.version.contains('aarch64')) {
      return 'arm64';
    }
    return 'amd64';
  }
}
