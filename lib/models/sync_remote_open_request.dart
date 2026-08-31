// 从同步配置跳转到文件管理页并打开指定桶/前缀。

class SyncRemoteOpenRequest {
  const SyncRemoteOpenRequest({
    required this.profileName,
    required this.bucket,
    required this.remotePrefix,
  });

  final String profileName;
  final String bucket;
  final String remotePrefix;

  factory SyncRemoteOpenRequest.fromJson(Map<String, dynamic> json) {
    return SyncRemoteOpenRequest(
      profileName: (json['profileName'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      remotePrefix: (json['remotePrefix'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'profileName': profileName,
    'bucket': bucket,
    'remotePrefix': remotePrefix,
  };
}

/// Reports whether a particular external-open ticket was still the newest
/// pending request when a file page finished or cancelled it.
typedef SyncRemoteOpenConsumer =
    bool Function(SyncRemoteOpenRequest request, int generation);
