import 'package:excel_herbal_erp/core/report_branch_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const branches = <Map<String, dynamic>>[
    {'id': 1, 'name': 'Branch 1', 'is_head_office': 1},
    {'id': 2, 'name': 'Palampur', 'is_head_office': 0},
    {'id': 3, 'name': 'Nagchala', 'is_head_office': false},
  ];

  test('Head Office flag replaces a generic Branch 1 label', () {
    expect(ReportBranchScope.label(1, branches), 'Head Office');
    expect(
      ReportBranchScope.caption(
        periodLabel: '01 Nov 2026 – 06 Nov 2026',
        branchId: 1,
        authorisedBranches: branches,
      ),
      '01 Nov 2026 – 06 Nov 2026 · Head Office',
    );
  });

  test('other authorised branches show their actual names', () {
    expect(ReportBranchScope.label(2, branches), 'Palampur');
    expect(ReportBranchScope.label(3, branches), 'Nagchala');
  });

  test('all-branch scope remains unchanged', () {
    expect(
      ReportBranchScope.caption(
        periodLabel: 'Live stock',
        branchId: null,
        authorisedBranches: branches,
      ),
      'Live stock',
    );
  });

  test('unlisted branch never borrows another branch name', () {
    expect(ReportBranchScope.label(999, branches), 'Authorised Branch');
    expect(
      ReportBranchScope.caption(
        periodLabel: 'Sales Summary',
        branchId: 999,
        authorisedBranches: branches,
      ),
      'Sales Summary · Authorised Branch',
    );
  });
}
