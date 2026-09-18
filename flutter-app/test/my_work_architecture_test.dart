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

    expect(main, contains("part 'my_work_attendance.dart';"));
    expect(main, contains("part 'my_work_leave_visit.dart';"));
    expect(main, isNot(contains('Widget _attendance()')));
    expect(main, isNot(contains('Widget _leaveVisit()')));
    expect(main, isNot(contains('Future<void> _attendanceAction(')));
    expect(main, isNot(contains('Future<void> _applyLeave()')));
    expect(main, isNot(contains('Future<void> _startVisit()')));

    expect(attendance, contains('extension _MyWorkAttendance'));
    expect(attendance, contains('Widget _attendance()'));
    expect(attendance, contains('Future<void> _attendanceAction('));

    expect(leaveVisit, contains('extension _MyWorkLeaveVisit'));
    expect(leaveVisit, contains('Widget _leaveVisit()'));
    expect(leaveVisit, contains('Future<void> _applyLeave()'));
    expect(leaveVisit, contains('Future<void> _completeVisit('));
    expect(leaveVisit, contains('Future<void> _startVisit()'));
  });
}
