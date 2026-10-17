abstract final class DailyOrderWorkflow {
  // One presentation contract for every Daily Order entry point. The underlying
  // cycle and request statuses remain untouched; this is display-only.
  static String statusLabel(String status) {
    const labels = <String, String>{
      'morning_draft': 'Draft',
      'stock_requested': 'Approval Pending',
      'approved': 'Issue Pending',
      'issued': 'Issued · Evening Pending',
      'evening_draft': 'Evening Draft',
      'evening_submitted': 'Final Post Pending',
      'completed': 'Completed',
      'cancelled': 'Cancelled',
      'rejected': 'Rejected',
    };
    return labels[status] ?? status;
  }

  static String orderStatusLabel(Map<String, dynamic> row) {
    final cycleStatus = '${row['status'] ?? ''}';
    final additionalStatus = '${row['additional_request_status'] ?? ''}';
    if (cycleStatus == 'issued' && additionalStatus == 'submitted') {
      return 'Issued · Additional Approval Pending';
    }
    if (cycleStatus == 'issued' && additionalStatus == 'approved') {
      return 'Issued · Additional Issue Pending';
    }
    return statusLabel(cycleStatus);
  }

  static const Set<String> _blockingAdditionalStatuses = {
    'draft',
    'submitted',
    'approved',
  };

  static bool canOperateOwnOrder(Iterable<String> capabilities) =>
      capabilities.contains('daily_order.self') ||
      capabilities.contains('daily_order.others');

  static bool canSubmitDraft(
    String cycleStatus,
    Iterable<String> capabilities,
  ) =>
      cycleStatus == 'morning_draft' && canOperateOwnOrder(capabilities);

  static bool canApproveRequest(
    String requestStatus,
    Iterable<String> capabilities, {
    int? requesterId,
    int? currentEmployeeId,
  }) {
    final isSelfApproval = requesterId != null &&
        currentEmployeeId != null &&
        requesterId == currentEmployeeId;
    return requestStatus == 'submitted' &&
        capabilities.contains('daily_order.approve') &&
        !isSelfApproval;
  }

  static bool canIssueRequest(
    String requestStatus,
    Iterable<String> capabilities, {
    int? requesterId,
    int? currentEmployeeId,
  }) {
    final isRequester = requesterId != null &&
        currentEmployeeId != null &&
        requesterId == currentEmployeeId;
    return requestStatus == 'approved' &&
        capabilities.contains('daily_order.issue') &&
        !isRequester;
  }

  static bool hasBlockingAdditionalRequests(
    Iterable<Map<String, dynamic>> requests,
  ) {
    for (final request in requests) {
      if ('${request['type']}' != 'additional') continue;
      if (_blockingAdditionalStatuses.contains('${request['status']}'))
        return true;
    }
    return false;
  }

  static String? eveningBlockReason({
    required String cycleStatus,
    required Iterable<Map<String, dynamic>> requests,
    required Iterable<String> capabilities,
  }) {
    if (!canOperateOwnOrder(capabilities)) {
      return 'Evening Closing ke liye Daily Order self/others permission required hai.';
    }
    if (cycleStatus != 'issued') {
      return 'Evening Closing sirf issued Daily Order par start ho sakti hai.';
    }
    if (hasBlockingAdditionalRequests(requests)) {
      return 'Additional Requirement abhi approval/issue pending hai. Pehle uska sequence complete karein.';
    }
    return null;
  }
}
