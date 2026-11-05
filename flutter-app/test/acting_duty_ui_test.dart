import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Acting Duty is exposed without mutating permanent authority UI', () {
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final admin = File(
      'lib/screens/administration/administration_screen.dart',
    ).readAsStringSync();
    final panel = File(
      'lib/screens/administration/acting_duty_admin_panel.dart',
    ).readAsStringSync();
    final profile =
        File('lib/screens/home/profile_screen.dart').readAsStringSync();

    expect(paths, contains("actingDelegations = '/administration/delegations'"));
    expect(paths, contains("actingInbox = '/administration/acting-inbox'"));
    expect(paths, contains("actingUnavailability = '/administration/unavailability'"));
    expect(paths, contains('delegationRevoke(int id)'));
    expect(paths, contains('unavailabilityRevoke(int id)'));

    expect(
      admin,
      contains("tabs.add(('Acting Duty', const ActingDutyAdminPanel()))"),
    );
    expect(panel, contains('New Delegation'));
    expect(panel, contains('Mark Unavailable'));
    expect(panel, contains('Exact-Action Delegations'));
    expect(panel, contains('does not change permanent roles, designations or branch authority'));
    expect(panel, isNot(contains('employeeRoles(')));
    expect(panel, isNot(contains('employeeOverrides(')));

    expect(profile, contains('const _ActingDutySummary()'));
    expect(profile, contains('Delegated Work Inbox'));
    expect(profile, contains('Permanent role and branch authority remain unchanged'));
  });
}
