import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('salary structure is enabled only with real backend and capabilities', () {
    final source = File('lib/screens/performance/performance_screen.dart')
        .readAsStringSync();
    final workspace = File('lib/screens/performance/compensation_workspace.dart')
        .readAsStringSync();
    final routes = File(
      '../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php',
    ).readAsStringSync();

    expect(source, contains("import 'compensation_workspace.dart';"));
    expect(source, contains('const CompensationWorkspace()'));
    expect(source, contains("'payroll.salary.manage'"));
    expect(workspace, contains('ApiPaths.salaryEmployees'));
    expect(workspace, contains("'payroll.salary.view'"));
    expect(workspace, isNot(contains("app.can('salary.manage')")));
    expect(routes, contains('/payroll/salary-structures'));
    for (final route in const [
      '/performance/rewards',
      '/performance/promotions',
    ]) {
      expect(routes, isNot(contains(route)), reason: route);
    }
  });

  test('future compensation source remains isolated for later backend completion', () {
    final source = File(
      'lib/screens/performance/compensation_workspace.dart',
    ).readAsStringSync();

    expect(source, contains('CompensationPolicy.validEffectiveDate'));
    expect(source, contains('CompensationPolicy.validatePromotionRequest'));
    expect(source, contains('CompensationPolicy.sameDesignation'));
  });
}
