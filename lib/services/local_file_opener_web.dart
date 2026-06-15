// Web builds cannot open local filesystem paths directly.

class LocalFileOpener {
  const LocalFileOpener._();

  static Future<void> openPath(String filePath) {
    throw UnsupportedError('Web 端不支持直接打开本地缓存文件');
  }
}
