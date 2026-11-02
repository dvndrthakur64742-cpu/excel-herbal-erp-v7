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


  test('bootstrap failure shows API error rather than generic null-data error', () {
    const failed = AppState(
      loading: false,
      authenticated: true,
      error: 'Network connection unavailable. Please try again.',
    );
    expect(failed.bootstrapReady, isFalse);
    expect(failed.bootstrapFailureMessage,
        'Network connection unavailable. Please try again.');
    expect(failed.bootstrapCompatibilityError, 'ERP startup data is unavailable.');
  });

  test('missing server date remains blocked with a specific contract error', () {
    const invalid = AppState(
      authenticated: true,
      bootstrap: {
        'business_date': '2026-02-30',
        'business_timezone': 'Asia/Kolkata',
        'server_timestamp': '2026-11-02T12:00:00Z',
        'api_contract': 'v7',
        'features': {'api_contract': 'v7'},
      },
    );
    expect(invalid.bootstrapReady, isFalse);
    expect(invalid.bootstrapFailureMessage,
        'ERP server business date is unavailable or invalid.');
  });

  test('a valid server contract is ready without local date fallback', () {
    const valid = AppState(
      authenticated: true,
      bootstrap: {
        'business_date': '2026-11-02',
        'business_timezone': 'Asia/Kolkata',
        'server_timestamp': '2026-11-02T12:00:00+00:00',
        'api_contract': '7.3.12-contract-refund-evidence-1',
        'features': {
          'api_contract': '7.3.12-contract-refund-evidence-1',
        },
      },
    );
    expect(valid.bootstrapReady, isTrue);
    expect(valid.usingFallbackBusinessDate, isFalse);
    expect(valid.businessDate, '2026-11-02');
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
