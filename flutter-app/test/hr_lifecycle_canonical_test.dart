import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HR lifecycle has one canonical implementation and one API path source', () {
    final organization =
        File('lib/screens/organization/organization_screen.dart').readAsStringSync();
    final hr =
        File('lib/screens/organization/hr_lifecycle_screen.dart').readAsStringSync();
    final actions =
        File('lib/screens/home/actions_screen.dart').readAsStringSync();

    expect(organization, contains('const HrLifecycleScreen(embedded: true)'));
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    expect(actions, contains('openConnectedAction(action.id)'));
    expect(shell, contains("case 'hr_lifecycle':"));
    expect(shell, contains('screen = const HrLifecycleScreen();'));
    expect(hr, contains('final bool embedded'));
    expect(hr, contains('ApiPaths.hrCandidates'));
    expect(hr, contains('ApiPaths.hrSeparations'));
    expect(hr, isNot(contains('HrApiPaths')));
    expect(
      File('lib/screens/organization/organization_hr.dart').existsSync(),
      isFalse,
    );
    expect(
      File('lib/screens/organization/hr_api_paths.dart').existsSync(),
      isFalse,
    );
  });
}
