import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Payroll exposes maker-checker salary revision history and review', () {
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final screen =
        File('lib/screens/performance/performance_screen.dart').readAsStringSync();

    expect(paths, contains('salaryRevisions(int employeeId)'));
    expect(paths, contains('salaryRevisionReview(int id)'));
    expect(screen, contains("title: const Text('Salary Revisions')"));
    expect(screen, contains('Salary revision submitted for independent approval.'));
    expect(screen, contains("app.can('payroll.salary.approve')"));
    expect(screen, contains("app.can('payroll.salary.manage')"));
    expect(screen, contains('creatorId != currentActorId'));
    expect(screen, contains('employeeId != currentActorId'));
    expect(
      screen,
      contains('Your own salary revision must be created by another authorised maker.'),
    );
  });
}
