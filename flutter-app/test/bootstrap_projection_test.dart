import 'package:excel_herbal_erp/core/bootstrap_projection.dart';
import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap projection safely normalizes identity and branches', () {
    final projection = BootstrapProjection.fromMap({
      'company': {'name': 'Excel Herbal'},
      'me': {
        'branch_ids': ['7', 7, 'bad', 9],
        'assigned_branch_id': '9',
        'branch_selector_visible': true,
        'capabilities': ['erp.access', 'reports.view', 'reports.view', ''],
        'employee': {
          'full_name': 'Dev Employee',
          'designation_code': 'BM',
          'designation_name': 'Branch Manager',
          'reporting_category': 'Branch Management',
        },
      },
      'branches': [
        {'id': '7', 'code': 'SHM', 'name': 'Shimla'},
        {'id': 9, 'code': 'SOL', 'name': 'Solan', 'is_head_office': 1},
        {'id': 'bad', 'code': 'BROKEN'},
        'not-a-map',
      ],
    });

    expect(projection.company.name, 'Excel Herbal');
    expect(projection.identity.branchIds, [7, 9]);
    expect(projection.identity.assignedBranchId, 9);
    expect(projection.identity.capabilities, ['erp.access', 'reports.view']);
    expect(projection.identity.employee.fullName, 'Dev Employee');
    expect(projection.branches.map((branch) => branch.id), [7, 9]);
    expect(projection.branches.last.isHeadOffice, isTrue);
  });

  test('AppState keeps raw map compatibility while using typed projection', () {
    const state = AppState(
      bootstrap: {
        'company': {'name': 'Excel Herbal'},
        'me': {
          'branch_ids': [7, 9],
          'branch_selector_visible': true,
          'capabilities': ['erp.access'],
          'employee': {
            'full_name': 'ERP User',
            'designation_code': 'BM',
          },
        },
        'branches': [
          {'id': 7, 'code': 'SHM', 'name': 'Shimla'},
          {'id': 9, 'code': 'SOL', 'name': 'Solan'},
        ],
      },
      currentBranchId: 9,
    );

    expect(state.branches, hasLength(2));
    expect(state.me['branch_ids'], [7, 9]);
    expect(state.employeeName, 'ERP User');
    expect(state.primaryDesignationCode, 'BM');
    expect(state.currentBranchName, 'Solan');
    expect(state.branchSelectorVisible, isTrue);
    expect(state.can('erp.access'), isTrue);
  });
}
