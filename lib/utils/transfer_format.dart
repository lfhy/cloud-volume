// Transfer formatting helpers keep byte and speed labels shared across queue views.

String formatBytesPerSecond(double bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}

String formatTransferCreatedAt(String raw, {DateTime? now}) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return '';
  }
  final local = parsed.toLocal();
  final current = now ?? DateTime.now();
  if (_isSameDay(local, current)) {
    return '创建于今天 ${_formatClock(local)}';
  }
  if (local.year == current.year) {
    return '创建于 ${_twoDigits(local.month)}-${_twoDigits(local.day)} ${_formatClock(local)}';
  }
  return '创建于 ${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} ${_formatClock(local)}';
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _formatClock(DateTime value) {
  return '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}:${_twoDigits(value.second)}';
}

String _twoDigits(int value) {
  return value >= 10 ? '$value' : '0$value';
}
