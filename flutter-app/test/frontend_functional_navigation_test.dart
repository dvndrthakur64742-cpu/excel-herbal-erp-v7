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
    expect(workspace, contains('final screen = MyWorkScreen('));
    expect(workspace, contains('child: screen,'));
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();
    expect(
      home,
      contains("import '../my_work/my_work_workspace_screen.dart';"),
    );
    expect(home, contains('SafeArea(child: MyWorkWorkspaceScreen())'));
    expect(home, isNot(contains("import '../my_work/my_work_screen.dart';")));
  });
  test('payroll UI matches backend mutation contract', () {
    final screen = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();
    final paths = File('lib/core/api_paths.dart').readAsStringSync();

    expect(
      paths,
      contains("'/payroll/runs/\$id/discard'"),
    );
    expect(screen, contains('ApiPaths.payrollDiscard(id)'));
    expect(screen, contains("'payment_account_id': paymentAccountId"));
    expect(screen, contains("'payment_date': paymentDate.text.trim()"));
    expect(screen, contains("'period_start': app.businessMonthStart"));
    expect(screen, contains("'period_end': app.businessDate"));
    expect(screen, isNot(contains("'from_date': app.businessMonthStart")));
    expect(screen, isNot(contains("'to_date': app.businessDate")));
    expect(screen, contains("item['full_name']"));
    expect(screen, contains("item['net_salary']"));
    expect(screen, contains('Discard Draft'));
    expect(screen, contains('calculation version missing'));
  });

  test('performance target picker is hierarchy scoped and hides raw employee ids', () {
    final screen = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final routes = File(
      '../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php',
    ).readAsStringSync();
    final service = File(
      '../backend/excel-herbal-erp-v7/src/Payroll/PayrollPerformanceService.php',
    ).readAsStringSync();

    expect(paths, contains("performanceTargetEmployees = '/performance/target-employees'"));
    expect(screen, contains('ApiPaths.performanceTargetEmployees'));
    expect(screen, contains("labelText: 'Employee'"));
    expect(screen, isNot(contains("labelText: 'Employee ID'")));
    expect(
      routes,
      contains(
        "['GET','/performance/target-employees','performance.target_employees',true]",
      ),
    );
    expect(service, contains('public static function targetEmployees'));
    expect(service, contains('Capabilities::PERFORMANCE_MANAGE'));
    expect(
      service,
      contains(
        'Guard::branchAny(\$a, \$branch, [Capabilities::PERFORMANCE_VIEW,Capabilities::PERFORMANCE_MANAGE])',
      ),
    );
    expect(
      service,
      contains("t.employee_id IN ('.implode(',', array_fill(0, count(\$visible), '%d')).')"),
    );
    expect(
      service,
      contains(
        "HierarchyScope::assertCanViewEmployee(\$a, (int) \$row['employee_id'])",
      ),
    );
    expect(service, contains('HierarchyScope::visibleEmployeeIds(\$a, \$branch)'));
    expect(service, contains('SELECT id,employee_code,full_name,designation_code'));
  });

  test('communication employee targeting is hierarchy scoped end to end', () {
    final screen = File(
      'lib/screens/communication/communication_screen.dart',
    ).readAsStringSync();
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final routes = File(
      '../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php',
    ).readAsStringSync();
    final adminService = File(
      '../backend/excel-herbal-erp-v7/src/Communication/CommunicationAdminService.php',
    ).readAsStringSync();
    final recoveryService = File(
      '../backend/excel-herbal-erp-v7/src/Recovery/RecoveryService.php',
    ).readAsStringSync();

    expect(
      paths,
      contains("communicationTargetEmployees = '/communication/target-employees'"),
    );
    expect(screen, contains('ApiPaths.communicationTargetEmployees'));
    expect(screen, isNot(contains('ApiPaths.employees')));
    expect(
      routes,
      contains(
        "['GET','/communication/target-employees','comm.target_employees',true]",
      ),
    );
    expect(adminService, contains('public static function targetEmployees'));
    expect(adminService, contains('Capabilities::COMM_MANAGE'));
    expect(
      adminService,
      contains('HierarchyScope::visibleEmployeeIds(\$a,\$branchId)'),
    );
    expect(
      adminService,
      contains('HierarchyScope::assertCanViewEmployee(\$a,\$employeeId)'),
    );
    expect(
      adminService,
      contains('SELECT id,employee_code,full_name,designation_code'),
    );
    expect(
      recoveryService,
      contains('HierarchyScope::assertCanViewEmployee(\$a,\$employeeId)'),
    );
  });

  test('acting duty mutations cannot bypass reporting hierarchy', () {
    final service = File(
      '../backend/excel-herbal-erp-v7/src/Administration/ActingDutyService.php',
    ).readAsStringSync();

    expect(
      service,
      contains('HierarchyScope::assertCanViewEmployee(\$a,\$delegator)'),
    );
    expect(
      service,
      contains('HierarchyScope::assertCanViewEmployee(\$a,\$delegate)'),
    );
    expect(
      service,
      contains('HierarchyScope::assertCanViewEmployee(\$a,\$employee)'),
    );
    expect(
      service,
      contains("HierarchyScope::canViewEmployee(\$a,(int)\$r['employee_id'])"),
    );
    expect(
      service,
      contains("HierarchyScope::canViewEmployee(\$a,(int)\$row['delegate_employee_id'])"),
    );
  });

  test('reporting manager changes cannot target hidden employees', () {
    final service = File(
      '../backend/excel-herbal-erp-v7/src/Organization/OrganizationEmployeeService.php',
    ).readAsStringSync();

    expect(
      service,
      contains('HierarchyScope::assertCanViewEmployee(\$a,\$managerId)'),
    );
    expect(
      service,
      contains('HierarchyScope::assertCanManageEmployeeAccess(\$a,\$employeeId)'),
    );
  });

  test('employee creation keeps designation baseline and extra role optional', () {
    final screen = File(
      'lib/screens/organization/organization_employees.dart',
    ).readAsStringSync();
    final guardrails = File(
      'lib/core/transaction_guardrails.dart',
    ).readAsStringSync();
    final masterData = File(
      '../backend/excel-herbal-erp-v7/src/Organization/OrganizationMasterDataService.php',
    ).readAsStringSync();

    expect(
      screen,
      contains("final canManageAccess = app.can('administration.access.manage')"),
    );
    expect(
      screen,
      contains("final canManageSalary = app.can('payroll.salary.manage')"),
    );
    expect(screen, contains("labelText: 'Additional Role (optional)'"));
    expect(
      screen,
      contains("if (canManageSalary) 'monthly_salary':"),
    );
    expect(screen, contains('? api.get(ApiPaths.roles)'));
    expect(guardrails, isNot(contains("return 'Role is required.'")));
    expect(
      masterData,
      contains(
        'public static function roles(Actor \$a):array{Guard::cap(\$a,Capabilities::ACCESS_MANAGE);',
      ),
    );
  });

  test('employee manage is not coupled to employee view for read prerequisites', () {
    final guard = File(
      '../backend/excel-herbal-erp-v7/src/Security/Guard.php',
    ).readAsStringSync();
    final employeeService = File(
      '../backend/excel-herbal-erp-v7/src/Organization/OrganizationEmployeeService.php',
    ).readAsStringSync();
    final masterData = File(
      '../backend/excel-herbal-erp-v7/src/Organization/OrganizationMasterDataService.php',
    ).readAsStringSync();

    expect(guard, contains('public static function branchAny'));
    expect(
      employeeService,
      contains(
        'Guard::branchAny(\$a,\$branch,[Capabilities::EMP_VIEW,Capabilities::EMP_MANAGE])',
      ),
    );
    expect(
      employeeService,
      contains(
        'Guard::any(\$a,[Capabilities::EMP_VIEW,Capabilities::EMP_MANAGE])',
      ),
    );
    expect(
      masterData,
      contains(
        'Guard::any(\$a,[Capabilities::EMP_VIEW,Capabilities::EMP_MANAGE])',
      ),
    );
  });

  test('daily others employee picker is hierarchy scoped without org-view dependency', () {
    final screen = File(
      'lib/screens/my_work/my_work_daily_order.dart',
    ).readAsStringSync();
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final routes = File(
      '../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php',
    ).readAsStringSync();
    final service = File(
      '../backend/excel-herbal-erp-v7/src/DailyOrder/DailyOrderService.php',
    ).readAsStringSync();

    expect(
      paths,
      contains("dailyTargetEmployees = '/daily/target-employees'"),
    );
    expect(screen, contains('ApiPaths.dailyTargetEmployees'));
    expect(screen, isNot(contains('ApiPaths.employees')));
    expect(
      routes,
      contains(
        "['GET','/daily/target-employees','daily.target_employees',true]",
      ),
    );
    expect(service, contains('public static function targetEmployees'));
    expect(service, contains('Capabilities::DAILY_OTHERS'));
    expect(
      service,
      contains(
        'Guard::any(\$a,[Capabilities::DAILY_SELF,Capabilities::DAILY_OTHERS])',
      ),
    );
    expect(
      service,
      contains('HierarchyScope::visibleEmployeeIds(\$a,\$branch)'),
    );
    expect(
      service,
      contains('SELECT id,employee_code,full_name,designation_code'),
    );
  });

  test('hr employee choices follow HR capability and hierarchy scope', () {
    final screen = File(
      'lib/screens/organization/hr_lifecycle_screen.dart',
    ).readAsStringSync();
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final routes = File(
      '../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php',
    ).readAsStringSync();
    final service = File(
      '../backend/excel-herbal-erp-v7/src/Organization/HrLifecycleService.php',
    ).readAsStringSync();

    expect(
      paths,
      contains("hrEmployeeChoices = '/organization/hr/employee-choices'"),
    );
    expect(screen, contains('ApiPaths.hrEmployeeChoices'));
    expect(screen, contains("'purpose': 'reporting'"));
    expect(screen, contains("'purpose': 'separation'"));
    expect(
      routes,
      contains(
        "['GET','/organization/hr/employee-choices','hr.employee_choices',true]",
      ),
    );
    expect(service, contains('public static function employeeChoices'));
    expect(service, contains('Capabilities::HR_REVIEW'));
    expect(service, contains('Capabilities::HR_MANAGE'));
    expect(
      service,
      contains('HierarchyScope::visibleEmployeeIds(\$a,\$branch)'),
    );
    expect(
      service,
      contains('HierarchyScope::manageableEmployeeIds(\$a)'),
    );
    expect(
      service,
      contains('HierarchyScope::assertCanManageEmployeeAccess(\$a,\$employeeId)'),
    );
  });

  test('acting duty employee picker uses delegation capability scope', () {
    final screen = File(
      'lib/screens/administration/acting_duty_admin_panel.dart',
    ).readAsStringSync();
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final routes = File(
      '../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php',
    ).readAsStringSync();
    final service = File(
      '../backend/excel-herbal-erp-v7/src/Administration/ActingDutyService.php',
    ).readAsStringSync();

    expect(
      paths,
      contains("actingEmployees = '/administration/acting-employees'"),
    );
    expect(screen, contains('ApiPaths.actingEmployees'));
    expect(screen, isNot(contains('ApiPaths.employees')));
    expect(
      routes,
      contains(
        "['GET','/administration/acting-employees','admin.acting_employees',true]",
      ),
    );
    expect(service, contains('public static function employeeChoices'));
    expect(service, contains('Capabilities::DELEGATION_MANAGE'));
    expect(
      service,
      contains('HierarchyScope::visibleEmployeeIds(\$a,\$branchId)'),
    );
    expect(
      service,
      contains('SELECT id,employee_code,full_name,designation_code'),
    );
  });

  test('access and salary employee pickers use their own authority scopes', () {
    final adminScreen = File(
      'lib/screens/administration/administration_screen.dart',
    ).readAsStringSync();
    final performanceScreen = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    final routes = File(
      '../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php',
    ).readAsStringSync();
    final accessService = File(
      '../backend/excel-herbal-erp-v7/src/Security/AccessService.php',
    ).readAsStringSync();
    final salaryService = File(
      '../backend/excel-herbal-erp-v7/src/Payroll/SalaryService.php',
    ).readAsStringSync();

    expect(
      paths,
      contains("accessEmployees = '/administration/access-employees'"),
    );
    expect(
      paths,
      contains("salaryEmployees = '/payroll/salary-employees'"),
    );
    expect(adminScreen, contains('ApiPaths.accessEmployees'));
    expect(performanceScreen, contains('ApiPaths.salaryEmployees'));
    expect(
      performanceScreen,
      isNot(contains("app.can('organization.employee.view') &&")),
    );
    expect(
      routes,
      contains(
        "['GET','/administration/access-employees','access.employees',true]",
      ),
    );
    expect(
      routes,
      contains(
        "['GET','/payroll/salary-employees','payroll.salary_employees',true]",
      ),
    );
    expect(accessService, contains('public static function employeeChoices'));
    expect(accessService, contains('Capabilities::ACCESS_MANAGE'));
    expect(
      accessService,
      contains('HierarchyScope::manageableEmployeeIds(\$a)'),
    );
    expect(salaryService, contains('public static function employeeChoices'));
    expect(
      salaryService,
      contains(
        'Guard::branchAny(\$a,\$branch,[Capabilities::SALARY_VIEW,Capabilities::SALARY_MANAGE,Capabilities::SALARY_APPROVE])',
      ),
    );
    expect(
      salaryService,
      contains('HierarchyScope::visibleEmployeeIds(\$a,\$branch)'),
    );
  });

  test('workforce management data follows reporting hierarchy', () {
    final service = File(
      '../backend/excel-herbal-erp-v7/src/Workforce/WorkforceService.php',
    ).readAsStringSync();

    expect(
      service,
      contains('HierarchyScope::visibleEmployeeIds(\$a,\$branch)'),
    );
    expect(
      service,
      contains('a.employee_id IN ({\$visible})'),
    );
    expect(
      service,
      contains('lr.employee_id IN ({\$visible})'),
    );
    expect(
      service,
      contains(
        "if(\$authority['mode']==='permanent')HierarchyScope::assertCanViewEmployee(\$a,(int)\$r['employee_id'])",
      ),
    );
  });

  test('production UI does not contain escaped Dart interpolation placeholders', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains(r'\${')) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Escaped interpolation renders literal placeholders in the UI: $offenders',
    );
  });

  test('professional detail views format backend statuses for users', () {
    final performance = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();
    final team = File(
      'lib/screens/organization/team_screen.dart',
    ).readAsStringSync();

    expect(performance, contains('BusinessFormat.status(status)'));
    expect(
      performance,
      contains("BusinessFormat.status(run['status'])"),
    );
    expect(
      team,
      contains("BusinessFormat.status((data['cycle'] as Map)['status'])"),
    );
    expect(
      team,
      contains("BusinessFormat.value('type', r['type'])"),
    );
  });

  test('administration exposes one-shot safe UAT cleanup', () {
    final source = File(
      'lib/screens/administration/administration_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'System Health'"));
    expect(source, contains('Resolve Safe UAT Anomalies'));
    expect(source, contains("'operation': 'resolve_uat_anomalies'"));
    expect(source, contains("'confirmation': 'RESOLVE_UAT_ANOMALIES'"));
    expect(source, contains('checkout times'));
    expect(source, contains('stock custody'));
  });

}