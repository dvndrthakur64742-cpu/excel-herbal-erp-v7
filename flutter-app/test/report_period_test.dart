import 'package:excel_herbal_erp/core/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server calendar rejects malformed and normalized invalid dates', () {
    expect(ReportPeriod.businessDay('2026-11-25'), DateTime(2026, 11, 25));
    for (final value in ['', '2026-02-30', '2026-11-25T00:00:00Z', '2026-13-01']) {
      expect(ReportPeriod.businessDay(value), isNull);
    }
  });
  test('quick periods include today and cross month or year correctly', () {
    final today = DateTime(2026, 1, 3);
    expect(ReportPeriod.preset(today, 'today'), (today, today));
    expect(ReportPeriod.preset(today, 'week'), (DateTime(2025, 12, 28), today));
    expect(ReportPeriod.preset(today, 'month'), (DateTime(2026, 1, 1), today));
    expect(ReportPeriod.preset(today, 'previous_month'),
      (DateTime(2025, 12, 1), DateTime(2025, 12, 31)));
    expect(ReportPeriod.preset(today, 'year'), (DateTime(2026, 1, 1), today));
  });
  test('previous month respects leap day', () {
    expect(ReportPeriod.preset(DateTime(2024, 3, 10), 'previous_month'),
      (DateTime(2024, 2, 1), DateTime(2024, 2, 29)));
  });
}
