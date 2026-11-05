import 'package:excel_herbal_erp/core/business_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessFormat.dateTime', () {
    test('treats zone-less backend DATETIME as UTC', () {
      const zoneLess = '2026-09-09 10:00:00';
      const explicitUtc = '2026-09-09T10:00:00Z';

      expect(
        BusinessFormat.dateTime(zoneLess),
        BusinessFormat.dateTime(explicitUtc),
      );
    });

    test('preserves explicit timezone semantics', () {
      const utc = '2026-09-09T10:00:00Z';
      const sameInstant = '2026-09-09T15:30:00+05:30';

      expect(
        BusinessFormat.dateTime(utc),
        BusinessFormat.dateTime(sameInstant),
      );
    });

    test('returns dash for blank values', () {
      expect(BusinessFormat.dateTime(''), '—');
      expect(BusinessFormat.dateTime('null'), '—');
    });
  });
}
