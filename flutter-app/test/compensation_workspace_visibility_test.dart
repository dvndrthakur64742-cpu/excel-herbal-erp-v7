import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('performance screen does not expose contract-only compensation workflow', () {
    final source = File('lib/screens/performance/performance_screen.dart')
        .readAsStringSync();
    final routes = File(
      '../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php',
    ).readAsStringSync();

    expect(source, isNot(contains("import 'compensation_workspace.dart';")));
    expect(source, isNot(contains('const CompensationWorkspace()')));
    expect(source, isNot(contains("'Compensation'")));

    for (final route in const [
      '/payroll/salary-structures',
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
