/// Status text must not transform missing evidence into a healthy system.
abstract final class OperationalHealthText {
  static bool needsAttention(String status, dynamic scheduler) =>
      status != 'healthy' || scheduler != 'recent';

  static String title(String status, dynamic scheduler) {
    if (status == 'attention') return 'Operational attention required';
    if (status != 'healthy' || scheduler == null) return 'System health unverified';
    if (scheduler != 'recent') return 'Attendance scheduler needs attention';
    return 'System healthy';
  }

  static String metric(dynamic value) =>
      value == null || '$value'.trim().isEmpty ? 'Unavailable' : '$value';

  static String approvalEmpty(int warnings) => warnings > 0
      ? 'Pending approvals could not be fully verified. Refresh to retry.'
      : 'No pending approvals in the loaded sources.';

  static String approvalCount(int count, int warnings) =>
      '$count pending item${count == 1 ? '' : 's'} in loaded sources'
      '${warnings > 0 ? ' · incomplete ($warnings source warnings)' : ''}.';
}
