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
    expect(performance, contains("'payroll.generate'"));
    expect(performance, contains("'payroll.approve'"));
    expect(performance, contains("'payroll.pay'"));
  });
  test('access management blocks hierarchy escape and privilege escalation', () {
    final access = File(
      '../backend/excel-herbal-erp-v7/src/Security/AccessService.php',
    ).readAsStringSync();

    expect(access, contains('HierarchyScope::assertCanManageEmployeeAccess(\$a,\$employeeId)'));
    expect(access, contains('assertCanDelegateCapabilities'));
    expect(access, contains("'authority_escalation_forbidden',403"));
    expect(access, contains('self::assertCanDelegateCapabilities(\$a,\$affectedCaps)'));
    expect(access, contains('self::assertCanDelegateCapabilities(\$a,array_merge(\$grants,\$denies))'));
  });

  test('shared-role and subordinate access scope are fail closed', () {
    final access = File(
      '../backend/excel-herbal-erp-v7/src/Security/AccessService.php',
    ).readAsStringSync();
    final hierarchy = File(
      '../backend/excel-herbal-erp-v7/src/Security/HierarchyScope.php',
    ).readAsStringSync();

    expect(hierarchy, contains('manageableEmployeeIds'));
    expect(hierarchy, contains('assertCanManageEmployeeAccess'));
    expect(hierarchy, contains("'employee_access_scope_forbidden',403"));
    expect(access, contains('assertRoleWithinAuthority'));
    expect(access, contains("'role_scope_forbidden',403"));
    expect(access, contains('array_merge(\$before,\$wanted)'));
    expect(access, contains('array_merge(\$grants,\$denies)'));
    expect(access, contains('array_column(\$before,\'capability\')'));
  });

  test('reserved system roles and employee mutations use central authority policy', () {
    final access = File(
      '../backend/excel-herbal-erp-v7/src/Security/AccessService.php',
    ).readAsStringSync();
    final branchAuthority = File(
      '../backend/excel-herbal-erp-v7/src/Security/BranchAuthority.php',
    ).readAsStringSync();
    final employee = File(
      '../backend/excel-herbal-erp-v7/src/Organization/OrganizationEmployeeService.php',
    ).readAsStringSync();
    final branch = File(
      '../backend/excel-herbal-erp-v7/src/Organization/OrganizationBranchService.php',
    ).readAsStringSync();

    expect(access, contains("'reserved_system_role_forbidden',403"));
    expect(access, contains('assertCanAdministerEmployeeIdentity'));
    expect(branchAuthority, contains('isCompanyWideAdmin'));
    expect(branchAuthority, contains('Capabilities::ACCESS_MANAGE'));
    expect(employee, contains('AccessService::assertCanDelegateCapabilities'));
    expect(employee, contains('AccessService::assertCanAdministerEmployeeIdentity'));
    expect(branch, contains('HierarchyScope::assertCanManageEmployeeAccess'));
    expect(branch, contains('HierarchyScope::hasCompanyWideSystemAuthority'));
  });

}
