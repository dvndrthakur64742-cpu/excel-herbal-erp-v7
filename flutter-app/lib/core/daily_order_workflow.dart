abstract final class DailyOrderWorkflow {
  static const Set<String> _blockingAdditionalStatuses = {
    'draft',
    'submitted',
    'reviewed',
    'approved',
    'awaiting_receipt',
  };

  static bool canOperateOwnOrder(Iterable<String> capabilities) =>
      capabilities.contains('daily_order.self') ||
      capabilities.contains('daily_order.others');

  static bool canSubmitDraft(
    String cycleStatus,
    Iterable<String> capabilities,
  ) =>
      cycleStatus == 'morning_draft' && canOperateOwnOrder(capabilities);

  /// Physical SM/ASM review is distinct from BM/HO final approval.
  /// Designation and beneficiary checks mirror the backend; server is final.
  static bool canReviewRequest(
    String requestStatus,
    Iterable<String> capabilities, {
    required String designationCode,
    int? requesterId,
    int? beneficiaryEmployeeId,
    int? currentEmployeeId,
  }) {
    const reviewers = {
      'SM', 'SALES_MANAGER', 'ASM', 'ASSISTANT_SALES_MANAGER',
      'SYSADMIN', 'SYSTEM_ADMIN', 'ADMIN', 'ADMINISTRATOR',
    };
    if (!reviewers.contains(designationCode.trim().toUpperCase())) {
      return false;
    }
    if (currentEmployeeId == null ||
        currentEmployeeId == requesterId ||
        currentEmployeeId == beneficiaryEmployeeId) {
      return false;
    }
    return requestStatus == 'submitted' &&
        capabilities.contains('daily_order.others');
  }

  static bool canApproveRequest(
    String requestStatus,
    Iterable<String> capabilities, {
    int? requesterId,
    int? currentEmployeeId,
  }) {
    final isSelfApproval = requesterId != null &&
        currentEmployeeId != null &&
        requesterId == currentEmployeeId;
    return requestStatus == 'reviewed' &&
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

  /// Only the named beneficiary may confirm a physical stock handover.
  /// The server rechecks branch, identity and row-level receipt state.
  static bool canReceiveRequest(
    String requestStatus,
    Iterable<String> capabilities, {
    int? beneficiaryEmployeeId,
    int? currentEmployeeId,
  }) =>
      requestStatus == 'awaiting_receipt' &&
      capabilities.contains('daily_order.self') &&
      beneficiaryEmployeeId != null &&
      currentEmployeeId != null &&
      beneficiaryEmployeeId == currentEmployeeId;

  /// A settled/rejected/withdrawn additional request must not block
  /// a subsequent request or evening closing in the summary menu.
  /// The backend rechecks every request, not only the latest summary row.
  static bool additionalQueueSettled(String status) =>
      status.isEmpty || const {'issued', 'cancelled', 'rejected'}.contains(status);

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
