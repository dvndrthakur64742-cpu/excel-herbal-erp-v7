import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

AppState _projected({
  required String designation,
  required List<String> capabilities,
  required List<String> sectionIds,
  List<int> branchIds = const [1],
}) {
  return AppState(
    loading: false,
    authenticated: true,
    currentBranchId: branchIds.isEmpty ? null : branchIds.first,
    bootstrap: {
      'me': {
        'employee': {
          'id': 99,
          'employee_code': 'ROLE-TEST',
          'full_name': 'Role Projection Test',
          'designation_code': designation,
          'designation_name': designation,
          'reporting_category': '',
          'additional_designations': const [],
          'additional_designations_authority_inherited': false,
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
        'sections': [
          for (final id in sectionIds) {'id': id, 'label': id},
        ],
        'bottom_nav': const [
          {'id': 'home', 'label': 'Home'},
          {'id': 'profile', 'label': 'Profile'},
        ],
      },
    },
  );
}

void main() {
  group('role-projected Home and workspace boundaries', () {
    test('field employee remains self-service only', () {
      final state = _projected(
        designation: 'STAFF',
        capabilities: const [
          'erp.access',
          'workforce.attendance.self',
          'workforce.field_visit.self',
          'workforce.leave.self',
          'daily_order.self',
          'performance.view',
          'communication.view',
        ],
        sectionIds: const ['home', 'my_work', 'communication'],
      );

      expect(state.sectionVisible('my_work'), isTrue);
      expect(state.sectionVisible('team'), isFalse);
      expect(state.can('reports.view'), isFalse);
      expect(state.managementDashboardVisible, isFalse);
      expect(state.erpToolsVisible, isTrue);
    });

    for (final role in const ['ASM', 'SM']) {
      test('$role gets team-scoped management overview only when projected', () {
        final state = _projected(
          designation: role,
          capabilities: const [
            'erp.access',
            'organization.employee.view',
            'workforce.attendance.manage',
            'reports.view',
          ],
          sectionIds: const ['home', 'my_work', 'team', 'reports'],
        );

        expect(state.sectionVisible('team'), isTrue);
        expect(state.can('reports.view'), isTrue);
        expect(state.managementDashboardVisible, isTrue);
        expect(state.can('administration.access.manage'), isFalse);
      });
    }

    test('branch manager gets branch management overview without system admin', () {
      final state = _projected(
        designation: 'BM',
        capabilities: const [
          'erp.access',
          'organization.employee.view',
          'workforce.attendance.manage',
          'reports.view',
          'sales.view',
          'inventory.view',
          'purchase.view',
          'finance.view',
        ],
        sectionIds: const [
          'home',
          'my_work',
          'team',
          'sales',
          'inventory',
          'purchase',
          'finance',
          'reports',
        ],
      );

      expect(state.managementDashboardVisible, isTrue);
      expect(state.can('administration.access.manage'), isFalse);
      expect(state.can('finance.accounting.view'), isFalse);
    });

    for (final role in const ['RM', 'RC', 'AGM', 'ZI']) {
      test('$role remains monitoring-oriented and branch-authority bounded', () {
        final state = _projected(
          designation: role,
          capabilities: const [
            'erp.access',
            'organization.employee.view',
            'workforce.attendance.manage',
            'finance.accounting.view',
            'reports.view',
          ],
          sectionIds: const ['home', 'team', 'finance', 'reports'],
          branchIds: const [1, 2],
        );

        expect(state.branches, hasLength(2));
        expect(state.managementDashboardVisible, isTrue);
        expect(state.can('finance.accounting.view'), isTrue);
        expect(state.can('administration.access.manage'), isFalse);
      });
    }

    for (final role in const ['CM', 'MD']) {
      test('$role gets executive reporting without implicit access management', () {
        final state = _projected(
          designation: role,
          capabilities: const [
            'erp.access',
            'organization.employee.view',
            'organization.branch.view',
            'finance.accounting.view',
            'reports.view',
            'administration.audit.view',
          ],
          sectionIds: const ['home', 'team', 'finance', 'reports', 'administration'],
          branchIds: const [1, 2, 3],
        );

        expect(state.managementDashboardVisible, isTrue);
        expect(state.can('administration.audit.view'), isTrue);
        expect(state.can('administration.access.manage'), isFalse);
      });
    }

    test('system admin can project administration without changing hierarchy rules', () {
      final state = _projected(
        designation: 'SYSADMIN',
        capabilities: const [
          'erp.access',
          'organization.employee.view',
          'workforce.attendance.manage',
          'reports.view',
          'finance.accounting.view',
          'administration.access.manage',
          'administration.audit.view',
        ],
        sectionIds: const ['home', 'team', 'reports', 'administration'],
        branchIds: const [1, 2, 3, 4],
      );

      expect(state.managementDashboardVisible, isTrue);
      expect(state.sectionVisible('administration'), isTrue);
      expect(state.can('administration.access.manage'), isTrue);
      expect(state.erpToolsVisible, isFalse,
          reason: 'Technical admin capabilities alone must not expose Account & Duty.');
    });

    test('accounting-only profile gets accounting but no team dashboard', () {
      final state = _projected(
        designation: 'ACCOUNTING',
        capabilities: const ['erp.access', 'finance.accounting.view'],
        sectionIds: const ['home', 'finance', 'reports'],
      );

      expect(state.can('finance.accounting.view'), isTrue);
      expect(state.can('reports.view'), isFalse);
      expect(state.sectionVisible('team'), isFalse);
      expect(state.managementDashboardVisible, isFalse);
    });

    test('zero authorised branches blocks business access for every role', () {
      final state = _projected(
        designation: 'SYSADMIN',
        capabilities: const [
          'erp.access',
          'reports.view',
          'organization.employee.view',
          'administration.access.manage',
        ],
        sectionIds: const ['home', 'team', 'reports', 'administration'],
        branchIds: const [],
      );

      expect(state.businessAccessBlocked, isTrue);
      expect(state.currentBranchId, isNull);
      expect(state.can('erp.access'), isTrue);
      expect(state.can('reports.view'), isFalse);
      expect(state.can('organization.employee.view'), isFalse);
      expect(state.can('administration.access.manage'), isFalse);
      expect(state.sectionVisible('team'), isFalse);
      expect(state.sectionVisible('reports'), isFalse);
      expect(state.sectionVisible('administration'), isFalse);
      expect(state.managementDashboardVisible, isFalse);
      expect(state.bottomNav.map((e) => e['id']), ['home', 'profile']);
    });
  });
}
