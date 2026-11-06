import 'dart:io';

import 'package:excel_herbal_erp/screens/communication/communication_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop, mobile and screen use one consistent Inbox & Tasks label', () {
    expect(kCommunicationWorkspaceTitle, 'Inbox & Tasks');
    final source = File('lib/shell/app_shell.dart').readAsStringSync();
    expect(source, contains("? kCommunicationWorkspaceTitle"));
  });

  test('communication tabs keep Tasks, Announcements and Notifications in order',
      () {
    final src =
        File('lib/screens/communication/communication_screen.dart')
            .readAsStringSync();
    final tasks = src.indexOf("Tab(text: 'Tasks')");
    final announcements = src.indexOf("Tab(text: 'Announcements')");
    final notifications = src.indexOf("Tab(text: 'Notifications')");
    expect(tasks, greaterThan(0));
    expect(announcements, greaterThan(tasks));
    expect(notifications, greaterThan(announcements));
    expect(src, contains('Choose Tasks, Announcements or Notifications'));
    expect(src, isNot(contains("title: const Text('Communication')")));
  });

  test('menu titles support two lines instead of clipping every long label',
      () {
    final src = File('lib/shell/app_shell.dart').readAsStringSync();
    final desktopStart = src.indexOf('Widget _desktopTile(');
    final desktopEnd = src.indexOf('Widget _desktopContent(', desktopStart);
    final drawerStart = src.indexOf('Widget _drawerTile(');
    final drawerEnd = src.indexOf('String _currentBranchLabel(', drawerStart);
    expect(desktopStart, greaterThanOrEqualTo(0));
    expect(desktopEnd, greaterThan(desktopStart));
    expect(drawerStart, greaterThanOrEqualTo(0));
    expect(drawerEnd, greaterThan(drawerStart));
    expect(src.substring(desktopStart, desktopEnd), contains('maxLines: 2'));
    expect(src.substring(drawerStart, drawerEnd), contains('maxLines: 2'));
  });
}
