/// Report dates use the server's business calendar, not the device clock.
abstract final class ReportPeriod {
  static DateTime? businessDay(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final date = DateTime.tryParse(value);
    if (date == null || date.year < 2000 || date.year > 2100 ||
        date.toIso8601String().substring(0, 10) != value) return null;
    return date;
  }

  static (DateTime, DateTime) preset(DateTime today, String value) {
    final end = DateTime(today.year, today.month, today.day);
    return switch (value) {
      'today' => (end, end),
      'week' => (DateTime(end.year, end.month, end.day - 6), end),
      'month' => (DateTime(end.year, end.month, 1), end),
      'previous_month' => (DateTime(end.year, end.month - 1, 1),
        DateTime(end.year, end.month, 0)),
      'year' => (DateTime(end.year, 1, 1), end),
      _ => throw ArgumentError.value(value, 'period'),
    };
  }
}
