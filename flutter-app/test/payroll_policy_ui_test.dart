import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Payroll leave policy is reachable and access-managed', () {
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final screen =
        File('lib/screens/performance/performance_screen.dart').readAsStringSync();
    final policy = File(
      'lib/screens/performance/payroll_policy_dialog.dart',
    ).readAsStringSync();

    expect(paths, contains("payrollPolicy = '/payroll/policy'"));
    expect(screen, contains("label: const Text('Payroll Policy')"));
    expect(screen, contains("app.can('payroll.approve')"));
    expect(
      screen,
      contains("app.can('administration.access.manage')"),
    );
    expect(policy, contains("'leave_types': leaveTypes"));
    expect(policy, contains("'reason': why"));
    expect(policy, contains('Paid leave'));
    expect(policy, contains('Unpaid leave'));
    expect(policy, contains('scheduled working days'));
  });
}
