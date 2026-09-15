import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('performance screen exposes compensation workspace behind exact capabilities', () {
    final source = File('lib/screens/performance/performance_screen.dart')
        .readAsStringSync();

    expect(source, contains("import 'compensation_workspace.dart';"));
    expect(source, contains("'Compensation'"));
    expect(source, contains('const CompensationWorkspace()'));

    for (final capability in const [
      'salary.view',
      'salary.manage',
      'salary.approve',
      'rewards.view',
      'rewards.manage',
      'rewards.approve',
      'rewards.pay',
      'promotion.view',
      'promotion.request',
      'promotion.approve',
    ]) {
      expect(source, contains("'$capability'"), reason: capability);
    }
  });

  test('compensation workspace uses strict effective-date and promotion preflight', () {
    final source = File('lib/screens/performance/compensation_workspace.dart')
        .readAsStringSync();

    expect(source, contains('CompensationPolicy.validEffectiveDate'));
    expect(source, contains('CompensationPolicy.validatePromotionRequest'));
    expect(source, contains('CompensationPolicy.sameDesignation'));
    expect(
      source,
      contains("trim().toLowerCase() == 'active'"),
      reason: 'employee/designation active-state checks must be normalized',
    );
    expect(source, isNot(contains('record nahi hai')));
    expect(source, isNot(contains('auto-change nahi hogi')));
  });
}
