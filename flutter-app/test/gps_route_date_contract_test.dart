import 'package:excel_herbal_erp/core/gps_route_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GPS route uses the server business day without UTC conversion', () {
    expect(
      GpsRouteQuery.forBusinessDate('2026-11-06'),
      {'from': '2026-11-06', 'to': '2026-11-06'},
    );
  });

  test('team GPS route retains the employee scope', () {
    expect(
      GpsRouteQuery.forBusinessDate('2028-02-29', employeeId: 42),
      {'employee_id': 42, 'from': '2028-02-29', 'to': '2028-02-29'},
    );
  });

  test('year/month boundary and valid leap day do not drift', () {
    for (final day in ['2026-12-31', '2027-01-01', '2028-02-29']) {
      final query = GpsRouteQuery.forBusinessDate(day);
      expect(query['from'], day);
      expect(query['to'], day);
    }
  });

  test('invalid dates and non-date ISO timestamps fail closed', () {
    for (final day in [
      '', '2026-02-31', '2026-11-6', '2026-11-06T00:00:00Z',
      '2026-13-01',
    ]) {
      expect(
        () => GpsRouteQuery.forBusinessDate(day),
        throwsFormatException,
      );
    }
    expect(
      () => GpsRouteQuery.forBusinessDate('2026-11-06', employeeId: 0),
      throwsArgumentError,
    );
  });
}
