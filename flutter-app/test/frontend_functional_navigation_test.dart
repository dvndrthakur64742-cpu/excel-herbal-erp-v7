import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quick actions route to their intended connected workflows', () {
    final source = File('lib/screens/home/actions_screen.dart').readAsStringSync();

    expect(source, contains("openConnectedAction('daily_create')"));
    expect(source, contains("openConnectedAction('evening')"));
    expect(source, contains("openConnectedAction('field_visit')"));
    expect(source, contains("openConnectedAction('attendance')"));
  });

  test('desktop approvals and global search keep independent tab state', () {
    final source = File('lib/shell/app_shell.dart').readAsStringSync();

    expect(source, contains("ValueKey('desktop-enterprise-approvals')"));
    expect(source, contains("ValueKey('desktop-enterprise-global-search')"));
    expect(source, contains('openConnectedAction: _openConnectedAction'));
  });

  test('all shell My Work entry points use the workspace wrapper', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    final workspace = File(
      'lib/screens/my_work/my_work_workspace_screen.dart',
    ).readAsStringSync();

    expect(
      shell,
      contains("import '../screens/my_work/my_work_workspace_screen.dart';"),
    );
    expect(shell, contains("'my_work' => const MyWorkWorkspaceScreen()"));
    expect(shell, contains("screen = const MyWorkWorkspaceScreen("));
    expect(shell, isNot(contains("import '../screens/my_work/my_work_screen.dart';")));
    expect(shell, isNot(contains("'my_work' => const MyWorkScreen()")));

    expect(workspace, contains("title: 'My Work'"));
    expect(workspace, contains('ModuleWorkspaceHeader('));
    expect(workspace, contains('app.currentBranchName.trim()'));
    expect(workspace, contains('child: MyWorkScreen('));
  });
}
