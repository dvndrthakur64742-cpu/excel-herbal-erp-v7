import 'dart:io';

import 'package:excel_herbal_erp/screens/communication/communication_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one communication workspace supports all three authorised entry tabs', () {
    const taskInbox = CommunicationScreen(initialTab: 0);
    const notices = CommunicationScreen(initialTab: 1);
    const notifications = CommunicationScreen(initialTab: 2);
    expect(taskInbox.initialTab, 0);
    expect(notices.initialTab, 1);
    expect(notifications.initialTab, 2);
  });

  test('task shortcut and notification bell open the one canonical inbox', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    final inbox =
        File('lib/screens/communication/communication_screen.dart')
            .readAsStringSync();
    expect(shell, contains("'tasks' => const CommunicationScreen(initialTab: 0)"));
    expect(shell, contains('CommunicationScreen(initialTab: 2)'));
    expect(shell, isNot(contains("import '../screens/communication/tasks_screen.dart'")));
    expect(shell, isNot(contains("'tasks' => const TasksScreen()")));
    expect(inbox, contains('initialIndex: widget.initialTab'));
    expect(inbox, contains('TasksScreen(initialTasks: tasks)'));
    expect(inbox, contains("app.can('communication.manage')"));
    expect(inbox, contains('ApiPaths.communicationSummary'));
  });

  test('desktop and mobile have searchable top-level access without duplicate search menu', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    expect(RegExp("tooltip: 'Global Search'").allMatches(shell).length, 2);
    expect(shell, contains("onPressed: () => _openModule('global_search')"));
    expect(shell, contains("onPressed: () => _selectDesktopRoute('global_search')"));
    expect(shell, contains("if (id == 'global_search') return !app.businessAccessBlocked;"));
    expect(shell, isNot(contains("_desktopTile(\n                    'global_search'")));
    expect(shell, isNot(contains("id: 'global_search',\n                      label: 'Global Search'")));
  });

  test('communication drawer entry is not duplicated for self-service task users', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    expect(shell, contains('final tasksInBottomBar = app.bottomNav.any('));
    expect(shell, contains("tasksInBottomBar && !app.can('communication.manage')"));
    expect(shell, contains("app.sectionVisible('communication')"));
    expect(shell, isNot(contains("_desktopTile('tasks', 'My Tasks'")));
    expect(kCommunicationWorkspaceTitle, 'Inbox & Tasks');
    expect(shell, contains('kCommunicationWorkspaceTitle'));
  });
}
