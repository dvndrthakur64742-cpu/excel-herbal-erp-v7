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
    expect(tracking, contains('Duty GPS is automatic. It stops only after checkout or the 5 PM duty cutoff.'));
    expect(coordinator, contains('ref.read(gpsTrackingProvider).sync()'));
    expect(tracking, isNot(contains('void employeeStart(')));
    expect(tracking, isNot(contains('void employeeStop(')));
  });

  test('duty attendance is materialized by the server and UI has no manual start/stop controls', () {
    final backend = File(
      '../backend/excel-herbal-erp-v7/src/Workforce/WorkforceService.php',
    ).readAsStringSync();
    final screen = File('lib/screens/my_work/my_work_attendance.dart').readAsStringSync();

    expect(backend, contains('AttendancePolicy::assertCheckInTime'));
    expect(backend, contains('AttendancePolicy::assertCheckOutTime'));
    expect(backend, isNot(contains('ensureScheduledAttendance')));
    final scheduler = File(
      '../backend/excel-herbal-erp-v7/src/Workforce/ScheduledAttendanceService.php',
    ).readAsStringSync();
    final plugin = File(
      '../backend/excel-herbal-erp-v7/src/Core/Plugin.php',
    ).readAsStringSync();
    expect(scheduler, contains("public const HOOK = 'eh7_scheduled_attendance_tick'")); 
    expect(scheduler, contains("'interval' => 300"));
    expect(scheduler, contains('AttendancePolicy::autoCheckOutDue'));
    expect(scheduler, contains('AttendancePolicy::AUTO_CHECK_OUT'));
    expect(scheduler, contains('check_in_at IS NOT NULL AND check_out_at IS NULL'));
    expect(scheduler, isNot(contains('INSERT INTO')));
    expect(scheduler, isNot(contains('GpsDutyPolicy::STOP')));
    expect(scheduler, contains("check_out_at"));
    expect(plugin, contains('ScheduledAttendanceService::boot()'));

    final policy = File('../backend/excel-herbal-erp-v7/src/Workforce/AttendancePolicy.php').readAsStringSync();
    expect(backend, contains("current_time('H:i:s')"));
    expect(policy, contains("SELF_CHECK_IN_START = '09:00:00'"));
    expect(policy, contains("SELF_CHECK_OUT_START = '18:00:00'"));
    expect(policy, contains("AUTO_CHECK_OUT = '20:00:00'"));
    expect(screen, contains("Text('Self Check-In')"));
    expect(screen, contains("Text('Self Check-Out')"));
    expect(screen, contains('PreviewReadOnlyPolicy.enabled'));
    expect(screen, contains('GPS Duty: automatic 10:30 AM–5 PM'));
    expect(screen, isNot(contains('manual duty toggle')));
    expect(scheduler, isNot(contains('GpsDutyPolicy::START')));
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
