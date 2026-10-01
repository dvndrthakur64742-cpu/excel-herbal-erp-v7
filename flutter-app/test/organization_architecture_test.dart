import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Organization keeps branch employee HR and product flows split', () {
    final main = File(
      'lib/screens/organization/organization_screen.dart',
    ).readAsStringSync();
    final branches = File(
      'lib/screens/organization/organization_branches.dart',
    ).readAsStringSync();
    final documents = File(
      'lib/screens/organization/organization_documents.dart',
    ).readAsStringSync();
    final employees = File(
      'lib/screens/organization/organization_employees.dart',
    ).readAsStringSync();
    final hr = File(
      'lib/screens/organization/hr_lifecycle_screen.dart',
    ).readAsStringSync();
    final products = File(
      'lib/screens/organization/organization_products.dart',
    ).readAsStringSync();
    final apiPaths = File('lib/core/api_paths.dart').readAsStringSync();

    expect(main, contains("part 'organization_branches.dart';"));
    expect(main, contains("part 'organization_documents.dart';"));
    expect(main, contains("part 'organization_employees.dart';"));
    expect(
      main,
      contains("const HrLifecycleScreen(embedded: true)"),
    );
    expect(main, isNot(contains("part 'organization_hr.dart';")));
    expect(main, contains("part 'organization_products.dart';"));
    expect(main, contains("'HR Lifecycle',"));
    expect(main, contains('void _setOrganizationState(VoidCallback update)'));
    expect(main, isNot(contains('Widget _branchesTab(AppState app)')));
    expect(main, isNot(contains('Widget _employeesTab(AppState app, dynamic api)')));
    expect(main, isNot(contains('Widget _productsTab(AppState app, dynamic api)')));
    expect(main.split('\n').length, lessThan(260));

    expect(branches, contains('extension _OrganizationBranchesFeature'));
    expect(documents, contains('extension _OrganizationDocumentsFeature'));
    expect(documents, contains('FilePicker.platform.pickFiles'));
    expect(documents, contains('openErpDocument'));
    expect(employees, contains('extension _OrganizationEmployeesFeature'));
    expect(hr, contains('class HrLifecycleScreen'));
    expect(hr, contains('New Candidate'));
    expect(hr, contains('Initiate Separation'));
    expect(products, contains('extension _OrganizationProductsFeature'));
    expect(apiPaths, contains("hrCandidates = '/organization/candidates'"));
    expect(apiPaths, contains("hrSeparations = '/organization/separations'"));
    expect(apiPaths, contains("candidateDocuments(int id)"));
    expect(apiPaths, contains("candidateDocumentUpload(int id)"));
    expect(branches, isNot(contains('setState(')));
    expect(documents, isNot(contains('setState(')));
    expect(employees, isNot(contains('setState(')));
    expect(hr, contains('widget.embedded'));
    expect(products, isNot(contains('setState(')));
  });
}
