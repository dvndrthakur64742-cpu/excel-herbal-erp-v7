import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Organization keeps branch employee and product flows split', () {
    final main = File(
      'lib/screens/organization/organization_screen.dart',
    ).readAsStringSync();
    final branches = File(
      'lib/screens/organization/organization_branches.dart',
    ).readAsStringSync();
    final employees = File(
      'lib/screens/organization/organization_employees.dart',
    ).readAsStringSync();
    final products = File(
      'lib/screens/organization/organization_products.dart',
    ).readAsStringSync();

    expect(main, contains("part 'organization_branches.dart';"));
    expect(main, contains("part 'organization_employees.dart';"));
    expect(main, contains("part 'organization_products.dart';"));
    expect(main, contains('void _setOrganizationState(VoidCallback update)'));
    expect(main, isNot(contains('Widget _branchesTab(AppState app)')));
    expect(main, isNot(contains('Widget _employeesTab(AppState app, dynamic api)')));
    expect(main, isNot(contains('Widget _productsTab(AppState app, dynamic api)')));
    expect(main.split('\n').length, lessThan(260));

    expect(branches, contains('extension _OrganizationBranchesFeature'));
    expect(employees, contains('extension _OrganizationEmployeesFeature'));
    expect(products, contains('extension _OrganizationProductsFeature'));
    expect(branches, isNot(contains('setState(')));
    expect(employees, isNot(contains('setState(')));
    expect(products, isNot(contains('setState(')));
  });
}
