/// Presentation-only selection of already-authorised Daily Order closings.
/// Original REST service rechecks branch, employee and order state on mutation.
abstract final class EveningOrderSelection {
  static const closingStatuses = {'issued', 'evening_draft'};

  static List<Map<String, dynamic>> candidates({
    required List<Map<String, dynamic>> rows,
    required String businessDate,
    required int? branchId,
    required int? actorEmployeeId,
    required bool selfAllowed,
    required bool othersAllowed,
  }) {
    // A multi-branch employee must choose the working branch explicitly.
    if (branchId == null || branchId <= 0 || (!selfAllowed && !othersAllowed)) {
      return const [];
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(businessDate)) {
      throw const FormatException('ERP business date is invalid.');
    }
    final seenIds = <int>{};
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      if ('${row['business_date'] ?? ''}' != businessDate ||
          !closingStatuses.contains('${row['status'] ?? ''}')) continue;
      final branch = int.tryParse('${row['branch_id'] ?? ''}');
      if (branch != branchId) continue;
      final employee = int.tryParse('${row['employee_id'] ?? ''}');
      if (employee == null || employee < 1) {
        throw const FormatException('Evening Order employee identity invalid.');
      }
      if (!othersAllowed && (actorEmployeeId == null || employee != actorEmployeeId)) {
        continue;
      }
      final id = int.tryParse('${row['id'] ?? ''}');
      if (id == null || id < 1 || !seenIds.add(id)) {
        throw const FormatException('Duplicate or invalid Evening Order identity.');
      }
      result.add(Map<String, dynamic>.unmodifiable(row));
    }
    result.sort((a, b) => (int.parse('${b['id']}')).compareTo(int.parse('${a['id']}')));
    return List.unmodifiable(result);
  }

  /// A cached dialog choice cannot bypass a newly revoked branch/role.
  static bool remainsAllowed({
    required Map<String, dynamic> selected,
    required String businessDate,
    required int? branchId,
    required int? actorEmployeeId,
    required bool selfAllowed,
    required bool othersAllowed,
  }) {
    try {
      return candidates(
        rows: [selected],
        businessDate: businessDate,
        branchId: branchId,
        actorEmployeeId: actorEmployeeId,
        selfAllowed: selfAllowed,
        othersAllowed: othersAllowed,
      ).length == 1;
    } on FormatException {
      return false;
    }
  }
}
