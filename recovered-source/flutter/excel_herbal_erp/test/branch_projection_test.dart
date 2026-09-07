import 'package:excel_herbal_erp/core/branch_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single authority auto-selects and hides selector', () {
    const projection = BranchProjection(assignedBranchId: 5, branchIds: [5]);
    expect(projection.selectorVisible, isFalse);
    expect(projection.automaticBranchId, 5);
    expect(projection.allows(5), isTrue);
    expect(projection.allows(8), isFalse);
  });

  test('multiple authorities require selector', () {
    const projection = BranchProjection(assignedBranchId: 5, branchIds: [5, 8]);
    expect(projection.selectorVisible, isTrue);
    expect(projection.automaticBranchId, isNull);
  });

  test('zero authority never creates an automatic branch', () {
    const projection = BranchProjection(assignedBranchId: 5, branchIds: []);
    expect(projection.selectorVisible, isFalse);
    expect(projection.automaticBranchId, isNull);
    expect(projection.allows(5), isFalse);
  });
}
