/// Restrict authenticated downloads to ERP document routes on the configured API.
/// A document response must never choose a different destination for bearer tokens.
Uri privateDocumentUri(String baseUrl, String value) {
  final base = Uri.parse(baseUrl);
  final target = Uri.tryParse(value);
  if (target == null ||
      !target.hasScheme ||
      target.userInfo.isNotEmpty ||
      target.hasQuery ||
      target.hasFragment ||
      !['https', 'http'].contains(target.scheme) ||
      target.scheme != base.scheme ||
      target.host != base.host ||
      target.port != base.port) {
    throw const FormatException('Invalid private document address.');
  }
  final root = base.path.replaceFirst(RegExp(r'/+$'), '');
  final path = target.path;
  if (!path.startsWith('$root/') ||
      !RegExp(r'^/organization/(employees|candidates)/[1-9]\d*/documents/[1-9]\d*/download$')
          .hasMatch(path.substring(root.length))) {
    throw const FormatException('Invalid private document route.');
  }
  return target;
}

String documentFilename(String? contentDisposition, String mimeType) {
  final encoded = RegExp("filename\\*=UTF-8''([^;]+)", caseSensitive: false)
      .firstMatch(contentDisposition ?? '')?.group(1);
  String name = '';
  if (encoded != null) {
    try {
      name = Uri.decodeComponent(encoded);
    } on FormatException {
      name = '';
    } on ArgumentError {
      // Invalid percent escapes can throw ArgumentError in Dart.
      name = '';
    }
  }
  name = name.replaceAll(RegExp(r'[/\\\x00-\x1f\x7f]'), '_').trim();
  if (name.isNotEmpty && name != '.' && name != '..') return name;
  final extension = {'application/pdf': 'pdf', 'image/jpeg': 'jpg',
    'image/png': 'png', 'image/webp': 'webp'}[mimeType] ?? 'bin';
  return 'document.$extension';
}
