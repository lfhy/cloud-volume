// Bucket settings keep per-bucket trash and readonly overrides out of the main config model.

bool? _bucketBoolFromDynamic(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return null;
}

String normalizeTrashDirectoryValue(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  if (trimmed.isEmpty) {
    return '.trash';
  }
  if (!trimmed.contains('/') && !trimmed.startsWith('.')) {
    return '.$trimmed';
  }
  return trimmed;
}

class BucketSettings {
  const BucketSettings({
    required this.readOnly,
    required this.trashEnabled,
    required this.trashDirectory,
  });

  factory BucketSettings.fromJson(Map<String, dynamic> json) {
    return BucketSettings(
      readOnly:
          _bucketBoolFromDynamic(json['readOnly'] ?? json['read_only']) ??
          false,
      trashEnabled: _bucketBoolFromDynamic(
        json['trashEnabled'] ?? json['trash_enabled'],
      ),
      trashDirectory: (json['trashDirectory'] ?? json['trash_directory'] ?? '')
          .toString(),
    );
  }

  final bool readOnly;
  final bool? trashEnabled;
  final String trashDirectory;

  bool get isTrashEnabled => trashEnabled == true;

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{'readOnly': readOnly};
    if (trashEnabled != null) {
      result['trashEnabled'] = trashEnabled;
    }
    if (trashDirectory.trim().isNotEmpty) {
      result['trashDirectory'] = normalizeTrashDirectoryValue(trashDirectory);
    }
    return result;
  }

  BucketSettings copyWith({
    bool? readOnly,
    bool? trashEnabled,
    bool clearTrashEnabled = false,
    String? trashDirectory,
  }) {
    return BucketSettings(
      readOnly: readOnly ?? this.readOnly,
      trashEnabled: clearTrashEnabled
          ? null
          : (trashEnabled ?? this.trashEnabled),
      trashDirectory: trashDirectory ?? this.trashDirectory,
    );
  }
}
