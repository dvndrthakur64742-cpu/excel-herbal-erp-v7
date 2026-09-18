import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('My Work attendance and leave features stay split from shell screen', () {
    final main = File(
      'lib/screens/my_work/my_work_screen.dart',
    ).readAsStringSync();
    final attendance = File(
      'lib/screens/my_work/my_work_attendance.dart',
    ).readAsStringSync();
    final leaveVisit = File(
      'lib/screens/my_work/my_work_leave_visit.dart',
    ).readAsStringSync();
    final daily = File(
      'lib/screens/my_work/my_work_daily.dart',
    ).readAsStringSync();
    final dailyOverview = File(
      'lib/screens/my_work/my_work_daily_overview.dart',
    ).readAsStringSync();
    final dailyOrder = File(
      'lib/screens/my_work/my_work_daily_order.dart',
    ).readAsStringSync();
    final dailyClosing = File(
      'lib/screens/my_work/my_work_daily_closing.dart',
    ).readAsStringSync();
    final dailyDetail = File(
      'lib/screens/my_work/my_work_daily_detail.dart',
    ).readAsStringSync();

    expect(main, contains("part 'my_work_attendance.dart';"));
    expect(main, contains("part 'my_work_leave_visit.dart';"));
    expect(main, contains("part 'my_work_daily.dart';"));
    expect(main, contains("part 'my_work_daily_overview.dart';"));
    expect(main, contains("part 'my_work_daily_order.dart';"));
    expect(main, contains("part 'my_work_daily_closing.dart';"));
    expect(main, contains("part 'my_work_daily_detail.dart';"));
    expect(main, isNot(contains('Widget _attendance()')));
    expect(main, isNot(contains('Widget _leaveVisit()')));
    expect(main, isNot(contains('Future<void> _attendanceAction(')));
    expect(main, isNot(contains('Future<void> _applyLeave()')));
    expect(main, isNot(contains('Future<void> _startVisit()')));
    expect(main, isNot(contains('Widget _daily()')));
    expect(main, isNot(contains('Future<void> _newDailyOrder()')));
    expect(main, isNot(contains('Future<void> _editEvening(')));
    expect(main, isNot(contains('Future<void> _finalPost(')));

    expect(attendance, contains('extension _MyWorkAttendance'));
    expect(attendance, contains('Widget _attendance()'));
    expect(attendance, contains('Future<void> _attendanceAction('));

    expect(leaveVisit, contains('extension _MyWorkLeaveVisit'));
    expect(leaveVisit, contains('Widget _leaveVisit()'));
    expect(leaveVisit, contains('Future<void> _applyLeave()'));
    expect(leaveVisit, contains('Future<void> _completeVisit('));
    expect(leaveVisit, contains('Future<void> _startVisit()'));

    expect(daily, contains('extension _MyWorkDaily'));
    expect(daily, contains('Widget _daily()'));
    expect(daily, contains('Future<void> _newDailyOrder()'));
    expect(daily, contains('Future<void> _editEvening('));
    expect(daily, contains('Future<void> _finalPost('));
    expect(daily.split('\n').length, lessThan(100));

    expect(dailyOverview, contains('extension _MyWorkDailyOverviewImpl'));
    expect(dailyOverview, contains('Widget _dailyImpl()'));
    expect(dailyOrder, contains('extension _MyWorkDailyOrderImpl'));
    expect(dailyOrder, contains('Future<void> _newDailyOrderImpl()'));
    expect(dailyOrder, contains('Future<void> _issueDailyImpl('));
    expect(dailyClosing, contains('extension _MyWorkDailyClosingImpl'));
    expect(dailyClosing, contains('Future<void> _editEveningImpl('));
    expect(dailyClosing, contains('Future<void> _finalPostImpl('));
    expect(dailyDetail, contains('extension _MyWorkDailyDetailImpl'));
    expect(dailyDetail, contains('Future<void> _showDailyImpl('));
  });
}
