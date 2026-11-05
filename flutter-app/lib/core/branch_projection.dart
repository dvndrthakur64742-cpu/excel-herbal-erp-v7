class BranchProjection {
  const BranchProjection({
    required this.assignedBranchId,
    required this.branchIds,
  });
  final int assignedBranchId;
  final List<int> branchIds;
  bool get selectorVisible => branchIds.length > 1;
  int? get automaticBranchId => branchIds.length == 1 ? branchIds.first : null;
  bool allows(int id) => branchIds.contains(id);
}
