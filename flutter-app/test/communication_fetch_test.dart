import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('communication workspace shares one summary fetch with tasks tab', () {
    final communication = File(
      'lib/screens/communication/communication_screen.dart',
    ).readAsStringSync();
    final tasks = File(
      'lib/screens/communication/tasks_screen.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'api\.get\(ApiPaths\.communicationSummary\)')
          .allMatches(communication)
          .length,
      1,
    );
    expect(communication, contains("summary['tasks']"));
    expect(communication, contains('TasksScreen(initialTasks: tasks)'));
    expect(tasks, isNot(contains('ApiPaths.communicationSummary')));
    expect(tasks, isNot(contains('AsyncPanel(')));
  });
}
