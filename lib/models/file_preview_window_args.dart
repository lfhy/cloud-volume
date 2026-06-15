// File preview window arguments cross the multi-window boundary as JSON.

import 'dart:convert';

import 'package:remote_storage/models/file_preview_source.dart';

class FilePreviewWindowArgs {
  const FilePreviewWindowArgs({
    required this.title,
    required this.kind,
    required this.localPath,
  });

  static const String businessId = 'file_preview';

  final String title;
  final FilePreviewKind kind;
  final String localPath;

  factory FilePreviewWindowArgs.fromJson(Map<String, dynamic> json) {
    return FilePreviewWindowArgs(
      title: json['title'] as String? ?? '预览',
      kind: _kindFromName(json['kind'] as String?),
      localPath: json['localPath'] as String? ?? '',
    );
  }

  factory FilePreviewWindowArgs.fromArguments(String arguments) {
    final json = jsonDecode(arguments) as Map<String, dynamic>;
    return FilePreviewWindowArgs.fromJson(json);
  }

  String toArguments() {
    return jsonEncode(<String, dynamic>{
      'businessId': businessId,
      'title': title,
      'kind': kind.name,
      'localPath': localPath,
    });
  }

  static bool matches(String arguments) {
    if (arguments.trim().isEmpty) return false;
    try {
      final json = jsonDecode(arguments) as Map<String, dynamic>;
      return json['businessId'] == businessId;
    } catch (_) {
      return false;
    }
  }

  static FilePreviewKind _kindFromName(String? name) {
    return FilePreviewKind.values.firstWhere(
      (kind) => kind.name == name,
      orElse: () => FilePreviewKind.unsupported,
    );
  }
}
