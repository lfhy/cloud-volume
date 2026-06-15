// Local file opener delegates to the desktop shell so cached files open natively.

import 'dart:io';

import 'package:remote_storage/platform/platform_info.dart';

class LocalFileOpener {
  const LocalFileOpener._();

  static Future<void> openPath(String filePath) async {
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
