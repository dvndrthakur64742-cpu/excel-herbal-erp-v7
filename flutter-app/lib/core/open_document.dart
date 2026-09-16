import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

Future<void> openErpDocument(ApiClient api, Map<String, dynamic> row) async {
  if (row['migration_required'] == true) {
    throw const FormatException('This document needs an administrator to migrate it.');
  }
  final url = '${row['url'] ?? ''}'.trim();
  if (url.isEmpty) throw const FormatException('Document is not available.');
  if (row['requires_auth'] == true) {
    final file = await api.downloadPrivateDocument(url);
    await Share.shareXFiles(
      [XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.filename)],
      fileNameOverrides: [file.filename],
    );
    return;
  }
  // Compatibility with the current 7.3.4 public-media response; never send tokens.
  final uri = Uri.tryParse(url);
  if (uri == null || !{'https', 'http'}.contains(uri.scheme) || uri.host.isEmpty) {
    throw const FormatException('Invalid document address.');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw const FormatException('Unable to open document.');
  }
}
