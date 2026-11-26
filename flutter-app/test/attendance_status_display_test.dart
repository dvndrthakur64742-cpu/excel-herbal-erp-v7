import 'package:excel_herbal_erp/core/attendance_status_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leave and holiday are not presented as attendance pending', () {
    String title(String reason) => AttendanceStatusDisplay.title(
        checkedIn: false, checkedOut: false, blockReason: reason);
    expect(title('approved_leave'), 'Approved leave');
    expect(title('holiday'), 'Holiday');
    expect(title('inactive_assignment'), 'Branch assignment required');
    expect(title('unknown'), 'Attendance pending');
  });
  test('existing punches take precedence over a block reason', () {
    expect(AttendanceStatusDisplay.title(checkedIn: true, checkedOut: false,
        blockReason: 'approved_leave'), 'Duty in progress');
    expect(AttendanceStatusDisplay.title(checkedIn: true, checkedOut: true,
        blockReason: 'holiday'), 'Duty completed for today');
  });
}
