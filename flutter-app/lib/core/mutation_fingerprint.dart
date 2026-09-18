import 'dart:convert';

String buildMutationFingerprint(
  String method,
  String path, {
  Map<String, dynamic>? query,
  Map<String, dynamic>? data,
}) {
  final canonicalQuery = _canonical(query ?? const <String, dynamic>{});
  final canonicalData = _canonical(data ?? const <String, dynamic>{});
  return '\$method|\$path|\${jsonEncode(canonicalQuery)}|\${jsonEncode(canonicalData)}';
}

dynamic _canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '\$key').toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) {
    return value.map(_canonical).toList(growable: false);
  }
  return value;
}
