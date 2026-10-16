import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee dashboard shows own sales and points without monetary fields', () {
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();
    final start = home.indexOf('class _PersonalPerformanceCard');
    final end = home.indexOf('class _ManagementOverview');
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final card = home.substring(start, end);

    expect(card, contains("row['sales_count']"));
    expect(card, contains("row['points']"));
    expect(card, contains("'Sales "));
    expect(card, isNot(contains('salary_fund')));
    expect(card, isNot(contains('BusinessFormat.money')));
    expect(card, isNot(contains('gross_amount')));
    expect(card, isNot(contains('outstanding_amount')));
  });

  test('self performance summary supplies a non-monetary sales count', () {
    final backend = File(
      '../backend/excel-herbal-erp-v7/src/Payroll/PayrollPerformanceService.php',
    ).readAsStringSync();
    final start = backend.indexOf('public static function summary(');
    final end = backend.indexOf('private static function canViewPeerPerformance', start);
    expect(start, isNonNegative);
    final summary = backend.substring(start, end);

    expect(summary, contains("'sales_count'"));
    expect(summary, contains("Db::table('counter_sales')"));
    expect(summary, contains("Db::table('daily_cycles')"));
    expect(summary, contains('You may view only your own performance.'));
    expect(summary, contains("'points'"));
  });

  test('GPS duty schedule is server-owned and has no employee start/stop controls', () {
    final policy = File(
      '../backend/excel-herbal-erp-v7/src/Workforce/GpsDutyPolicy.php',
    ).readAsStringSync();
    final tracking = File('lib/core/gps_tracking_service.dart').readAsStringSync();
    final coordinator =
        File('lib/core/gps_tracking_coordinator.dart').readAsStringSync();

    expect(policy, contains("public const START='10:30:00'"));
    expect(policy, contains("public const STOP='17:00:00'"));
    expect(policy, contains("'manual_start_allowed'=>false"));
    expect(policy, contains("'manual_stop_allowed'=>false"));
    expect(tracking, contains('_scheduleTimer = Timer(delay'));
    expect(tracking, contains('_stopTimer = Timer(delay'));
    expect(tracking, contains('Refuse to turn tracking off'));
    expect(coordinator, contains('ref.read(gpsTrackingProvider).sync()'));
    expect(tracking, isNot(contains('void employeeStart(')));
    expect(tracking, isNot(contains('void employeeStop(')));
  });

  test('route widget overlays recorded points on attributed OpenStreetMap road tiles', () {
    final route = File('lib/widgets/gps_route_view.dart').readAsStringSync();
    expect(route, contains('https://tile.openstreetmap.org/'));
    expect(route, contains('Road map · recorded GPS route'));
    expect(route, contains('© OpenStreetMap contributors'));
    expect(route, contains('Route timeline'));
    expect(route, contains('_RoadRoutePainter'));
    expect(route, isNot(contains('Recorded GPS trace · not a road map')));
  });
}
