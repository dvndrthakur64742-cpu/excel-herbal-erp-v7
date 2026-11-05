import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/document_download.dart';

void main() {
  const base = 'https://office.excelherbal.in/wp-json/excel-herbal-erp/v7';
  const path = '/organization/employees/1/documents/2/download';
  test('accepts exact same-origin private document route', () {
    expect(privateDocumentUri(base, '$base$path').path, endsWith(path));
    expect(privateDocumentUri(base, '$base/organization/candidates/4/documents/5/download').host,
        'office.excelherbal.in');
  });
  for (final url in [
    'https://untrusted.invalid/wp-json/excel-herbal-erp/v7$path',
    'http://office.excelherbal.in/wp-json/excel-herbal-erp/v7$path',
    '$base$path?token=secret',
    '$base$path#fragment',
    '$base/organization/employees/1/documents/2/deactivate',
    '$base/../../wp/v2/users',
    '/organization/employees/1/documents/2/download',
    'https://user@office.excelherbal.in/wp-json/excel-herbal-erp/v7$path',
    'https://office.excelherbal.in:444/wp-json/excel-herbal-erp/v7$path',
  ]) {
    test('rejects unsafe destination: $url', () {
      expect(() => privateDocumentUri(base, url), throwsFormatException);
    });
  }
  test('decodes and sanitizes server filename', () {
    expect(documentFilename("attachment; filename*=UTF-8''salary%20slip.pdf", 'application/pdf'),
        'salary slip.pdf');
    expect(documentFilename("attachment; filename*=UTF-8''..%2Fsecret.pdf", 'application/pdf'),
        '.._secret.pdf');
    expect(documentFilename(null, 'image/png'), 'document.png');
    expect(documentFilename("attachment; filename*=UTF-8''%ZZ", 'application/pdf'), 'document.pdf');
  });
}
