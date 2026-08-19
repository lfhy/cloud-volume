// Parsing helpers shared by the unified remote-task model.
// JSON parsing stays separate so the core task model remains compact.
part of 'remote_task.dart';

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

List<Object?> _records(Object? value) =>
    value is List ? value.cast<Object?>() : const <Object?>[];

List<String> _strings(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const <String>[];

RemoteTaskPhase _phaseFromWire(Object? value) {
  return switch (value?.toString().trim().toLowerCase()) {
    'quiet_period' || 'quiet-period' => RemoteTaskPhase.quietPeriod,
    'dependency' || 'blocked' => RemoteTaskPhase.dependency,
    'provider' ||
    'uploading' ||
    'downloading' ||
    'deleting' ||
    'moving' ||
    'copying' => RemoteTaskPhase.provider,
    'verification' || 'verifying' => RemoteTaskPhase.verification,
    'cleanup' => RemoteTaskPhase.cleanup,
    'local' => RemoteTaskPhase.local,
    _ => RemoteTaskPhase.unknown,
  };
}
