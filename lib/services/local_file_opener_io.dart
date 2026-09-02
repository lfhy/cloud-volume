// Local file opener delegates to the desktop shell so cached files open natively.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:remote_storage/platform/platform_info.dart';

class LocalFileOpener {
  const LocalFileOpener._();

  static const MethodChannel _androidChannel = MethodChannel(
    'cloud_volume/external_file_opener',
  );

  static Future<void> openPath(String filePath) async {
    if (isAndroidPlatform) {
      await _androidChannel.invokeMethod<void>('openFile', {'path': filePath});
      return;
    }
    final command = _commandFor(filePath);
    final result = await Process.run(command.executable, command.arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        command.executable,
        command.arguments,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  static _ShellCommand _commandFor(String filePath) {
    if (isMacOSPlatform) {
      return _ShellCommand('open', <String>[filePath]);
    }
    if (isLinuxPlatform) {
      return _ShellCommand('xdg-open', <String>[filePath]);
    }
    if (isWindowsPlatform) {
      // Dart passes each argv element directly to cmd.exe. `start` still needs
      // the empty title argument, but quoting the path here creates literal
      // quote characters and makes Explorer report a nonexistent file.
      return _ShellCommand('cmd', <String>['/c', 'start', '', filePath]);
    }
    throw UnsupportedError('当前平台暂不支持直接打开本地文件');
  }
}

class _ShellCommand {
  const _ShellCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
