class DateTimeText {
  const DateTimeText._();

  /// Backend stores operational DATETIME values with current_time('mysql', true),
  /// i.e. UTC without a timezone suffix. Render those values in the user's local
  /// device timezone so India users do not see 5:30-hour-old timestamps.
  static String local(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty || raw == '-' || raw.toLowerCase() == 'null') return '-';
    final parsed = _parseBackendDateTime(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    return '${_two(local.day)}-${_two(local.month)}-${local.year} ${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
  }

  static String compact(dynamic value) {
    final rendered = local(value);
    if (rendered == '-') return rendered;
    final parts = rendered.split(' ');
    return parts.length == 2 ? parts[1] : rendered;
  }

  static DateTime? _parseBackendDateTime(String raw) {
    var text = raw.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
    text = text.replaceFirst(' ', 'T');
    final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
    return DateTime.tryParse(hasZone ? text : '${text}Z');
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
