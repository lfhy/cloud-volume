// 文件管理页 WebDAV 入口：展示当前桶的浏览器/客户端访问地址。

part of 'file_manager_page.dart';

extension _FileManagerPageWebDav on _FileManagerPageState {
  void _showWebDavEntry(FileManagerBucketEntry bucket) {
    final uri = widget.api.webDavUri(bucket.bucket.name);
    if (uri == null) {
      _showPageMessage(title: 'WebDAV 不可用', message: '当前客户端未提供 WebDAV 地址。');
      return;
    }
    _showPageMessage(
      title: 'WebDAV 地址',
      message: '请使用初始化或系统设置中配置的 WebDAV 账号密码访问：\n$uri',
    );
  }
}
