// 传输快照模型：承接 Go bridge 返回的统一对象操作状态。

class TransferSnapshot {
  const TransferSnapshot({
    required this.id,
    required this.type,
    required this.bucket,
    required this.key,
    required this.localPath,
    required this.targetPath,
    required this.status,
    required this.statusDetail,
    required this.createdAt,
    required this.bytesCompleted,
    required this.totalBytes,
    required this.itemsCompleted,
    required this.totalItems,
    required this.currentFileKey,
    required this.currentFileBytesCompleted,
    required this.currentFileTotalBytes,
    required this.speedBytes,
    this.error,
  });

  factory TransferSnapshot.fromJson(Map<String, dynamic> json) {
    return TransferSnapshot(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
      localPath: (json['localPath'] ?? '').toString(),
      targetPath: (json['targetPath'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      statusDetail: (json['statusDetail'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      bytesCompleted: (json['bytesCompleted'] ?? 0) as int,
      totalBytes: (json['totalBytes'] ?? 0) as int,
      itemsCompleted: (json['itemsCompleted'] ?? 0) as int,
      totalItems: (json['totalItems'] ?? 0) as int,
      currentFileKey: (json['currentFileKey'] ?? '').toString(),
      currentFileBytesCompleted:
          (json['currentFileBytesCompleted'] ?? 0) as int,
      currentFileTotalBytes: (json['currentFileTotalBytes'] ?? 0) as int,
      speedBytes: (json['speedBytes'] ?? 0).toDouble(),
      error: json['error']?.toString(),
    );
  }

  final String id;
  final String type;
  final String bucket;
  final String key;
  final String localPath;
  final String targetPath;
  final String status;
  final String statusDetail;
  final String createdAt;
  final int bytesCompleted;
  final int totalBytes;
  final int itemsCompleted;
  final int totalItems;
  final String currentFileKey;
  final int currentFileBytesCompleted;
  final int currentFileTotalBytes;
  final double speedBytes;
  final String? error;
}
