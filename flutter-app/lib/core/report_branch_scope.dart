/// Read-only branch labels for reports and their exports.
///
/// The selected ID is the existing authorised ERP branch filter. Display
/// names never expand query scope or grant access.
class ReportBranchScope {
  const ReportBranchScope._();

  static String label(
    int branchId,
    List<Map<String, dynamic>> authorisedBranches,
  ) {
    for (final branch in authorisedBranches) {
      if (int.tryParse('${branch['id'] ?? ''}') != branchId) continue;
      final headOffice = branch['is_head_office'];
      if (headOffice == true ||
          headOffice == 1 ||
          '${headOffice ?? ''}'.trim() == '1') {
        return 'Head Office';
      }
      final name = '${branch['name'] ?? ''}'.trim();
      return name.isNotEmpty && name.toLowerCase() != 'null'
          ? name
          : 'Authorised Branch';
    }
    return 'Authorised Branch';
  }

  static String caption({
    required String periodLabel,
    required int? branchId,
    required List<Map<String, dynamic>> authorisedBranches,
  }) {
    if (branchId == null) return periodLabel;
    return '$periodLabel · ${label(branchId, authorisedBranches)}';
  }
}
