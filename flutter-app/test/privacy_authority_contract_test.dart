import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sensitive capabilities are explicit and senior roles are branch bounded', () {
    final caps = File(
      '../backend/excel-herbal-erp-v7/src/Security/Capabilities.php',
    ).readAsStringSync();
    final actor = File(
      '../backend/excel-herbal-erp-v7/src/Security/ActorResolver.php',
    ).readAsStringSync();

    expect(caps, contains("EMP_CONTACT_VIEW='organization.employee.contact.view'"));
    expect(caps, contains("EMP_DOCUMENT_DOWNLOAD='organization.employee.document.download'"));
    expect(caps, contains("HR_DOCUMENT_DOWNLOAD='organization.hr.document.download'"));
    expect(caps, contains("GPS_TEAM_VIEW='workforce.gps.team.view'"));
    expect(caps, contains("SALARY_VIEW='payroll.salary.view'"));
    expect(caps, contains("SALARY_MANAGE='payroll.salary.manage'"));
    expect(caps, contains("SALARY_APPROVE='payroll.salary.approve'"));

    expect(
      actor,
      contains(
        "['SYSADMIN','SYSTEM_ADMIN','ADMIN','ADMINISTRATOR'],true",
      ),
    );
    expect(
      actor,
      isNot(
        contains(
          "'ZI','ZONAL_INSPECTOR','CM','CHAIRMAN','CHAIRMAN_MANAGING_DIRECTOR','MD','MANAGING_DIRECTOR'],true",
        ),
      ),
    );
  });

  test('account duty duplicate is removed from shell navigation', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    final profile = File('lib/screens/home/profile_screen.dart').readAsStringSync();
    final tools = File('lib/screens/tools/erp_tools_screen.dart').readAsStringSync();

    expect(shell, isNot(contains("label: 'My Account & Duty'")));
    expect(shell, isNot(contains("'Account & Duty',")));
    expect(profile, contains('ErpToolsScreen(accountOnly: true)'));
    expect(profile, contains("label: const Text('Account & Security')"));
    expect(tools, contains('this.accountOnly = false'));
  });

  test('GPS and salary revision UI use granular authorities', () {
    final team = File('lib/screens/organization/team_screen.dart').readAsStringSync();
    final performance = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();

    expect(team, contains("app.can('workforce.gps.team.view')"));
    expect(performance, contains("'payroll.salary.view'"));
    expect(performance, contains("'payroll.salary.manage'"));
    expect(performance, contains("'payroll.salary.approve'"));
    expect(performance, contains("'Salary'"));
    expect(
      performance,
      contains("app.canAny(const [\n      'payroll.generate',\n      'payroll.approve',\n      'payroll.pay',"),
    );
  });
}
