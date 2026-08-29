/// Shortens a filename while preserving its extension for narrow cards.
String compactDisplayName(String name, {int maxLength = 18}) {
  if (name.length <= maxLength) return name;
  final dot = name.lastIndexOf('.');
  final extension = dot > 0 && dot < name.length - 1 ? name.substring(dot) : '';
  final stem = extension.isEmpty ? name : name.substring(0, dot);
  final available = maxLength - extension.length - 3;
  if (available < 2) return '${name.substring(0, maxLength - 3)}...';
  final head = (available + 1) ~/ 2;
  final tail = available - head;
  return '${stem.substring(0, head)}...${stem.substring(stem.length - tail)}$extension';
}
