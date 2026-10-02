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
    expect(service, contains('HierarchyScope::visibleEmployeeIds(\$a, \$branch)'));
    expect(service, contains('SELECT id,employee_code,full_name,designation_code'));
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