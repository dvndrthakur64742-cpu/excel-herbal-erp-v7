import 'dart:convert';

/// Stable identity of a report request, independent of map insertion order.
/// A changed branch, date, category or endpoint must load a new result before
/// displaying or exporting rows under the new report scope.
String reportQueryIdentity(String path, Map<String, dynamic> query) {
  final keys = query.keys.toList()..sort();
  return jsonEncode([
    path,
    {for (final key in keys) key: query[key]},
  ]);
}
