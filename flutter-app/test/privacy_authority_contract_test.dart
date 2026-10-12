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

  test('attendance writes are not blocked by unavailable geolocation', () {
    final attendance = File(
      'lib/screens/my_work/my_work_attendance.dart',
    ).readAsStringSync();
    expect(attendance, contains('Position? p;'));
    expect(attendance, contains('locationWarning = UiError.message(e);'));
    expect(attendance, contains("'lat': p?.latitude"));
    expect(attendance, contains("'lng': p?.longitude"));
    expect(attendance, contains('Attendance location not captured:'));
    expect(
      attendance,
      contains('_position(timeLimit: const Duration(seconds: 8))'),
    );
    final work = File('lib/screens/my_work/my_work_screen.dart').readAsStringSync();
    expect(work, contains('Duration timeLimit = const Duration(seconds: 20)'));
    expect(work, contains('timeLimit: timeLimit'));
  });

  test('existing accounting and reconciliation reports are exposed by capability', () {
    final reports = File(
      'lib/screens/reports/reports_screen.dart',
    ).readAsStringSync();
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final records = File('lib/widgets/records_list.dart').readAsStringSync();

    expect(reports, contains("if (app.can('reports.view'))"));
    expect(reports, contains("if (app.can('finance.accounting.view'))"));
    for (final report in [
      'stock_reconciliation',
      'finance_reconciliation',
      'receivables',
      'payables',
      'profit_loss',
      'balance_sheet',
      'trial',
    ]) {
      expect(reports, contains("'$report'"));
    }
    for (final path in [
      'stockReconciliation',
      'financeReconciliation',
      'receivables',
      'payables',
      'profitLoss',
      'balanceSheet',
    ]) {
      expect(paths, contains(path));
    }
    expect(records, contains("'stock_reconciliation' => const ["));
    expect(records, contains("'finance_reconciliation' => const ["));
  });

  test('employee access save does not misreport post-commit refresh failures', () {
    final administration = File(
      'lib/screens/administration/administration_screen.dart',
    ).readAsStringSync();
    expect(
      administration,
      contains('String? refreshWarning;'),
    );
    expect(administration, contains('catch (refreshError)'));
    expect(
      administration,
      contains('refreshWarning = UiError.message(refreshError);'),
    );
    expect(
      administration,
      contains('Employee access saved atomically. \$applied effective permissions, but app refresh failed:'),
    );
    expect(
      administration,
      contains('Inherit uses designation and role permissions. Grant adds access. Deny blocks access'),
    );
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

  test('canonical communication and password UX stay aligned', () {
    final tools = File(
      'lib/screens/tools/erp_tools_screen.dart',
    ).readAsStringSync();
    final communication = File(
      'lib/screens/communication/communication_screen.dart',
    ).readAsStringSync();
    final appState = File('lib/state/app_state.dart').readAsStringSync();
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    final navigation = File(
      '../backend/excel-herbal-erp-v7/src/App/NavigationProjection.php',
    ).readAsStringSync();

    expect(tools, isNot(contains('Widget _communicationTab')));
    expect(tools, isNot(contains('Future<void> _createTask()')));
    expect(tools, contains('password.text.length < 10'));
    expect(tools, contains('Password must contain at least 10 characters.'));
    expect(communication, contains("app.can('communication.manage')"));
    expect(communication, contains("title: 'Management Actions'"));
    expect(communication, contains('Future<void> _createTask()'));
    expect(communication, contains('Future<void> _createAnnouncement'));
    expect(communication, contains('Future<void> _createNotification()'));
    expect(communication, contains('child: BranchSelector()'));
    expect(communication, isNot(contains('Due At (optional ISO date/time)')));
    expect(appState, isNot(contains("'communication.view',")));
    expect(navigation, contains("['id'=>'tasks','label'=>'My Tasks']"));
    expect(shell, contains("_desktopTile('tasks', 'My Tasks'"));
  });

  test('management dashboard loads independent summaries concurrently', () {
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();

    expect(home, contains('final salesFuture = _safeRows('));
    expect(home, contains("app.can('daily_order.others')"));
    expect(home, contains("app.can('performance.view')"));
    expect(home, contains('final rows = await Future.wait(['));
    expect(home, contains('Future<List<Map<String, dynamic>>> _safeRows'));
  });

  test('business date inputs use picker widgets instead of raw format typing', () {
    final finance = File('lib/screens/finance/finance_screen.dart').readAsStringSync();
    final bank = File('lib/screens/finance/finance_bank.dart').readAsStringSync();
    final periods = File('lib/screens/finance/finance_periods.dart').readAsStringSync();
    final organization = File(
      'lib/screens/organization/organization_screen.dart',
    ).readAsStringSync();
    final employees = File(
      'lib/screens/organization/organization_employees.dart',
    ).readAsStringSync();
    final products = File(
      'lib/screens/organization/organization_products.dart',
    ).readAsStringSync();
    final hr = File(
      'lib/screens/organization/hr_lifecycle_screen.dart',
    ).readAsStringSync();
    final performance = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();
    final acting = File(
      'lib/screens/administration/acting_duty_admin_panel.dart',
    ).readAsStringSync();

    expect(finance, contains("business_date_field.dart"));
    expect(organization, contains("business_date_field.dart"));
    expect(hr, contains("business_date_field.dart"));
    expect(performance, contains("business_date_field.dart"));
    expect(bank, contains('BusinessDateField('));
    expect(periods, contains('BusinessDateField('));
    expect(employees, contains('BusinessDateField('));
    expect(products, contains('BusinessDateField('));
    expect(acting, contains('BusinessDateTimeField('));

    for (final source in [bank, periods, employees, products, hr, performance]) {
      expect(source, isNot(contains('labelText: \'From YYYY-MM-DD\'')));
      expect(source, isNot(contains('labelText: \'To YYYY-MM-DD\'')));
      expect(source, isNot(contains('Joining Date YYYY-MM-DD')));
      expect(source, isNot(contains('Effective Date YYYY-MM-DD')));
      expect(source, isNot(contains('Payment Date (YYYY-MM-DD)')));
    }
    expect(acting, isNot(contains('Starts At YYYY-MM-DDTHH:MM')));
    expect(acting, isNot(contains('Ends At YYYY-MM-DDTHH:MM')));
  });

  test('Accounts report review is snapshot-bound and maker-checker protected', () {
    final reports = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    final queue = File('lib/screens/reports/report_review_queue.dart').readAsStringSync();
    final service = File(
      '../backend/excel-herbal-erp-v7/src/Reporting/ReportReviewService.php',
    ).readAsStringSync();
    expect(reports, contains("'accounts_review'"));
    expect(reports, contains('Submit for Accounts Review'));
    expect(reports, contains('ApiPaths.reportReviewDecision(id)'));
    expect(queue, contains('Confirm approval'));
    expect(queue, contains('Confirm rejection'));
    expect(service, contains('report_review_maker_checker'));
    expect(service, contains('report_snapshot_stale'));
  });

}
