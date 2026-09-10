import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

AppState _state({
  required List<String> capabilities,
  required List<Map<String, dynamic>> sections,
  List<Map<String, dynamic>> bottomNav = const [],
  List<Map<String, dynamic>> additionalDesignations = const [],
  String reportingCategory = '',
  bool additionalAuthorityInherited = false,
  List<int> branchIds = const [1],
}) {
  return AppState(
    loading: false,
    authenticated: true,
    currentBranchId: branchIds.isEmpty ? null : branchIds.first,
    bootstrap: {
      'me': {
        'employee': {
          'id': 10,
          'full_name': 'Role Test User',
          'designation_code': 'STAFF',
          'designation_name': 'Staff',
          'reporting_category': reportingCategory,
          'additional_designations': additionalDesignations,
          'additional_designations_authority_inherited':
              additionalAuthorityInherited,
        },
        'branch_ids': branchIds,
        'branch_selector_visible': branchIds.length > 1,
        'capabilities': capabilities,
      },
      'branches': [
        for (final id in branchIds)
          {'id': id, 'code': 'B$id', 'name': 'Branch $id'},
      ],
      'navigation': {
        'sections': sections,
        'bottom_nav': bottomNav,
      },
    },
  );
}

void main() {
  test('additional designation never manufactures authority', () {
    final state = _state(
      capabilities: const ['erp.access'],
      sections: const [
        {'id': 'home', 'label': 'Home'},
      ],
      reportingCategory: 'SYSTEM_ADMIN',
      additionalDesignations: const [
        {
          'designation_code': 'SYSADMIN',
          'designation_name': 'System Administrator',
          'assignment_type': 'temporary',
        },
      ],
    );

    expect(state.reportingCategory, 'SYSTEM_ADMIN');
    expect(state.additionalDesignations, hasLength(1));
    expect(state.can('administration.access.manage'), isFalse);
    expect(state.managementDashboardVisible, isFalse);
    expect(state.erpToolsVisible, isFalse);
  });

  test('reporting category alone is grouping and never grants authority', () {
    final state = _state(
      capabilities: const ['erp.access'],
      sections: const [
        {'id': 'home', 'label': 'Home'},
      ],
      reportingCategory: 'SYSTEM_ADMIN',
    );

    expect(state.reportingCategory, 'SYSTEM_ADMIN');
    expect(state.can('reports.view'), isFalse);
    expect(state.can('workforce.attendance.manage'), isFalse);
    expect(state.can('administration.access.manage'), isFalse);
    expect(state.managementDashboardVisible, isFalse);
  });

  test('authority inheritance marker cannot manufacture client permissions', () {
    final state = _state(
      capabilities: const ['erp.access'],
      sections: const [
        {'id': 'home', 'label': 'Home'},
      ],
      additionalAuthorityInherited: true,
      additionalDesignations: const [
        {
          'designation_code': 'MD',
          'designation_name': 'Managing Director',
          'assignment_type': 'additional',
        },
      ],
    );

    expect(state.additionalDesignationAuthorityInherited, isTrue);
    expect(state.can('reports.view'), isFalse);
    expect(state.can('organization.employee.manage'), isFalse);
    expect(state.managementDashboardVisible, isFalse);
  });

  test('reports-only role does not get management dashboard', () {
    final state = _state(
      capabilities: const ['erp.access', 'reports.view'],
      sections: const [
        {'id': 'home', 'label': 'Home'},
        {'id': 'reports', 'label': 'Reports Centre'},
      ],
    );

    expect(state.can('reports.view'), isTrue);
    expect(state.sectionVisible('team'), isFalse);
    expect(state.managementDashboardVisible, isFalse);
  });

  test('management dashboard requires both team projection and reports.view', () {
    final state = _state(
      capabilities: const ['erp.access', 'reports.view'],
      sections: const [
        {'id': 'home', 'label': 'Home'},
        {'id': 'team', 'label': 'Team Operations'},
        {'id': 'reports', 'label': 'Reports Centre'},
      ],
    );

    expect(state.managementDashboardVisible, isTrue);
  });

  test('stale ERP Tools bottom-nav entry is hidden without tool authority', () {
    final state = _state(
      capabilities: const ['erp.access'],
      sections: const [
        {'id': 'home', 'label': 'Home'},
      ],
      bottomNav: const [
        {'id': 'home', 'label': 'Home'},
        {'id': 'erp_tools', 'label': 'ERP Tools'},
        {'id': 'profile', 'label': 'Profile'},
      ],
    );

    expect(state.erpToolsVisible, isFalse);
    expect(state.bottomNav.map((e) => e['id']), ['home', 'profile']);
  });

  test('technical admin caps alone do not expose account duty workspace', () {
    final state = _state(
      capabilities: const [
        'erp.access',
        'administration.access.manage',
        'administration.audit.view',
      ],
      sections: const [
        {'id': 'home', 'label': 'Home'},
        {'id': 'administration', 'label': 'Administration'},
      ],
      bottomNav: const [
        {'id': 'home', 'label': 'Home'},
        {'id': 'erp_tools', 'label': 'ERP Tools'},
        {'id': 'profile', 'label': 'Profile'},
      ],
    );

    expect(state.erpToolsVisible, isFalse);
    expect(state.bottomNav.map((e) => e['id']), ['home', 'profile']);
  });

  test('ERP Tools remains visible when projected capability needs it', () {
    final state = _state(
      capabilities: const ['erp.access', 'communication.view'],
      sections: const [
        {'id': 'home', 'label': 'Home'},
      ],
      bottomNav: const [
        {'id': 'home', 'label': 'Home'},
        {'id': 'erp_tools', 'label': 'ERP Tools'},
      ],
    );

    expect(state.erpToolsVisible, isTrue);
    expect(state.bottomNav.map((e) => e['id']), ['home', 'erp_tools']);
  });

  test('aggregate branch scope remains limited to authorised branch ids', () {
    final state = AppState(
      loading: false,
      authenticated: true,
      currentBranchId: null,
      bootstrap: const {
        'me': {
          'employee': {
            'id': 10,
            'full_name': 'Aggregate Scope Test',
            'designation_code': 'RM',
          },
          'branch_ids': [1, 2],
          'branch_selector_visible': true,
          'capabilities': ['erp.access', 'reports.view'],
        },
        'branches': [
          {'id': 1, 'code': 'B1', 'name': 'Branch 1'},
          {'id': 2, 'code': 'B2', 'name': 'Branch 2'},
        ],
        'navigation': {
          'sections': [
            {'id': 'home', 'label': 'Home'},
            {'id': 'reports', 'label': 'Reports Centre'},
          ],
          'bottom_nav': [],
        },
      },
    );

    expect(state.currentBranchId, isNull);
    expect(state.currentBranchName, 'All Authorised Branches');
    expect(state.branches.map((e) => e['id']), [1, 2]);
    expect(state.businessAccessBlocked, isFalse);
  });

  test('zero branch authority blocks business access even with capabilities', () {
    final state = _state(
      capabilities: const ['erp.access', 'reports.view'],
      sections: const [
        {'id': 'home', 'label': 'Home'},
        {'id': 'reports', 'label': 'Reports Centre'},
      ],
      branchIds: const [],
    );

    expect(state.businessAccessBlocked, isTrue);
    expect(state.currentBranchId, isNull);
  });
}
