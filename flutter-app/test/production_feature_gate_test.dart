import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only backend-backed salary compensation is exposed', () {
    final performance = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();
    final workspace = File(
      'lib/screens/performance/compensation_workspace.dart',
    ).readAsStringSync();

    expect(performance, contains("import 'compensation_workspace.dart';"));
    expect(performance, contains("'Compensation'"));
    expect(performance, contains("'rewards.approve'"));
    expect(performance, contains('const CompensationWorkspace()'));
    expect(performance, contains("'payroll.salary.approve'"));
    expect(performance, isNot(contains("'Rewards / Penalties'")));
    expect(performance, isNot(contains("'Promotions / Increments'")));
    expect(workspace, contains('ApiPaths.salaryStructures'));
    expect(workspace, contains("app.can('payroll.salary.manage')"));
    expect(workspace, contains("app.can('payroll.salary.approve')"));
  });

  test('performance target action follows create then approve backend contract', () {
    final performance = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();

    expect(performance, contains(".post(ApiPaths.targetApprove(id), data: const {})"));
    expect(performance, contains("title: Text('Approve Target #\$id')"));
    expect(performance, isNot(contains('ApiPaths.performanceTarget(id)')));
    expect(performance, isNot(contains('.put(')));
  });
}
