/// Bind a mutating Daily Order UI action to exactly one canonical request.
///
/// A cached request-status-only lookup can select the wrong historical request
/// when the same cycle has an initial and one or more additional requests.
/// This is only an extra frontend preflight. Backend REST remains authoritative
/// for effective branch, hierarchy, maker/checker and current DB status.
abstract final class DailyOrderActionTarget {
  static Map<String, dynamic>? select({
    required Map<String, dynamic> detail,
    required String action,
    required Iterable<String> capabilities,
    required int? actorEmployeeId,
  }) {
    if (actorEmployeeId == null || actorEmployeeId <= 0) return null;
    final cycle = detail['cycle'];
    if (cycle is! Map) return null;
    final cycleId = int.tryParse('${cycle['id'] ?? ''}');
    final status = '${cycle['status'] ?? ''}';
    if (cycleId == null || cycleId <= 0) return null;

    String? requestType;
    Set<String> expectedStatuses;
    String? capability;
    switch (action) {
      case 'approve':
      case 'reject':
        if (status == 'stock_requested') {
          requestType = 'initial';
        } else if (status == 'issued') {
          requestType = 'additional';
        } else {
          return null;
        }
        capability = 'daily_order.approve';
        expectedStatuses = const {'submitted'};
        break;
      case 'issue':
        if (status == 'approved') {
          requestType = 'initial';
        } else if (status == 'issued') {
          requestType = 'additional';
        } else {
          return null;
        }
        capability = 'daily_order.issue';
        expectedStatuses = const {'approved'};
        break;
      case 'cancel_additional':
        if (status != 'issued') return null;
        requestType = 'additional';
        expectedStatuses = const {'draft', 'submitted', 'approved'};
        if (!capabilities.contains('daily_order.self') &&
            !capabilities.contains('daily_order.others')) {
          return null;
        }
        break;
      default:
        return null;
    }

    if (capability != null && !capabilities.contains(capability)) return null;
    final raw = detail['requests'];
    if (raw is! List) return null;

    Map<String, dynamic>? chosen;
    for (final record in raw) {
      if (record is! Map) return null;
      final row = Map<String, dynamic>.from(record);
      final id = int.tryParse('${row['id'] ?? ''}');
      final parentId = int.tryParse('${row['daily_cycle_id'] ?? ''}');
      if (id == null || id <= 0 || parentId != cycleId) return null;
      if ('${row['type']}' != requestType ||
          !expectedStatuses.contains('${row['status']}')) continue;

      // Approver and issuer must never act as the original request maker.
      // Missing requester metadata must not silently become authorization.
      if (capability != null) {
        final requesterId = int.tryParse('${row['requested_by'] ?? ''}');
        if (requesterId == null ||
            requesterId <= 0 ||
            requesterId == actorEmployeeId) return null;
      }
      // Even if a stale response contains two actionable requests, do not
      // guess which one the user meant or issue multiple mutations.
      if (chosen != null) return null;
      chosen = row;
    }
    return chosen;
  }
}
