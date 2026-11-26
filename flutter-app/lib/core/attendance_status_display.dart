/// Presentation only: punch eligibility still comes exclusively from the API.
abstract final class AttendanceStatusDisplay {
  static String title({required bool checkedIn, required bool checkedOut,
      required Object? blockReason}) {
    if (checkedOut) return 'Duty completed for today';
    if (checkedIn) return 'Duty in progress';
    return switch (blockReason) {
      'approved_leave' => 'Approved leave',
      'holiday' => 'Holiday',
      'inactive_assignment' => 'Branch assignment required',
      _ => 'Attendance pending',
    };
  }
}