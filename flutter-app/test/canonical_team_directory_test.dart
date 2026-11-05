import 'dart:io';

import 'package:excel_herbal_erp/widgets/guided_workspace_switcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one authorised Team Directory replaces duplicate employee tabs', () {
    final team =
        File('lib/screens/organization/team_screen.dart').readAsStringSync();

    // Reporting readiness and the staff directory reuse the same branch-scoped
    // API result. Organization remains the single employee-master owner.
    expect(RegExp(r'ApiPaths\.employees').allMatches(team).length, 1);
    expect(team, contains("'Team Directory'"));
    expect(team, contains("ValueKey('canonical-team-directory')"));
    expect(team, contains('Employee master changes belong to Organization.'));
    expect(team, contains("'branch_id': app.currentBranchId"));
    expect(team, isNot(contains("'Hierarchy',\n        AsyncPanel(")));
    expect(team, isNot(contains("'Employees',\n        AsyncPanel(")));

    // An unauthorised viewer must not see a staff list, and management
    // actions must retain their original capability checks.
    expect(team, contains("if (app.can('organization.employee.view'))"));
    expect(team, contains("app.can('organization.employee.manage')"));
    expect(team, contains('onOpenEmployee: _employeeDesignations'));
  });

  test('inactive employees remain visible but do not cause false alerts', () {
    final team =
        File('lib/screens/organization/team_screen.dart').readAsStringSync();
    expect(team, contains("row['status'] ?? 'active'"));
    expect(team, contains("toLowerCase() != 'active'"));
    expect(team, contains("Reporting Hierarchy Readiness"));
    expect(team, contains("if (rows.length >= 200)"));
    expect(team, contains("Showing up to 200 employees."));
  });

  test('guided navigation explains the merged directory without new actions',
      () {
    final section = GuidedWorkspaceSection.forTab('Team Directory');
    expect(section.title, 'Team Directory & Reporting');
    expect(section.description, contains('Employee master editing'));
    expect(GuidedWorkspaceSection.forTab('Daily Orders').title,
        'Review Daily Orders');
  });

  test('task inbox remains canonical and is never implemented twice', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    final communication = File(
      'lib/screens/communication/communication_screen.dart',
    ).readAsStringSync();
    final task = File('lib/screens/communication/tasks_screen.dart')
        .readAsStringSync();

    // PR #39 already routed both My Tasks entry points into the same inbox.
    expect(shell, contains("'tasks' => const CommunicationScreen(initialTab: 0)"));
    expect(communication, contains('TasksScreen(initialTasks: tasks)'));
    expect(task, isNot(contains('ApiPaths.communicationSummary')));
    expect(task, isNot(contains('AsyncPanel(')));
  });
}
