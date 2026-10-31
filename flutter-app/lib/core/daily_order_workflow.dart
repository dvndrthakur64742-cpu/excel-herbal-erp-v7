abstract final class DailyOrderWorkflow {
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
