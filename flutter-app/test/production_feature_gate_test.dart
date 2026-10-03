import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('advanced compensation workspace stays hidden without backend contract', () {
    final performance = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();

    expect(
      performance,
      contains('Do not expose an interactive UAT workflow that can only fail at runtime.'),
    );
    expect(performance, isNot(contains("import 'compensation_workspace.dart';")));
    expect(performance, isNot(contains("'Compensation'")));
    expect(performance, isNot(contains('CompensationWorkspace(')));
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
