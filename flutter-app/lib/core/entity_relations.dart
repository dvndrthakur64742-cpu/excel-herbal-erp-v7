abstract final class EntityRelations {
  static int? normalizeId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value'.trim());
  }

  static bool sameId(dynamic left, dynamic right) {
    final a = normalizeId(left);
    final b = normalizeId(right);
    return a != null && b != null && a == b;
  }

  static List<Map<String, dynamic>> byForeignKey(
    Iterable<Map<String, dynamic>> rows,
    String key,
    dynamic id,
  ) {
    return rows.where((row) => sameId(row[key], id)).toList();
  }

  static Map<String, dynamic>? firstById(
    Iterable<Map<String, dynamic>> rows,
    dynamic id, {
    String key = 'id',
  }) {
    for (final row in rows) {
      if (sameId(row[key], id)) return row;
    }
    return null;
  }

  static double sum(Iterable<Map<String, dynamic>> rows, String key) {
    var total = 0.0;
    for (final row in rows) {
      final value = row[key];
      if (value is num) {
        total += value.toDouble();
      } else {
        total += double.tryParse('${value ?? ''}'.replaceAll(',', '')) ?? 0;
      }
    }
    return total;
  }
}
