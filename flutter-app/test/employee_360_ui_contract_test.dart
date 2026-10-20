import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';

void main() {
  test('Employee 360 endpoint builders match canonical V7 read-only routes', () {
    expect(ApiPaths.employee360(42), '/organization/employees/42/360');
    expect(ApiPaths.employee360Register(42),
        '/organization/employees/42/360/register');
  });

  test('Employee 360 screen is reachable from existing employee profile', () {
    final parent = File('lib/screens/organization/organization_screen.dart')
        .readAsStringSync();
    final employees = File('lib/screens/organization/organization_employees.dart')
        .readAsStringSync();
    final profile = File('lib/screens/organization/employee_360_screen.dart')
        .readAsStringSync();
    expect(parent, contains("import 'employee_360_screen.dart';"));
    expect(employees, contains('Employee360Screen('));
    expect(employees, contains("title: const Text('Sales, Points & Stock')"));
    expect(profile, contains('ApiPaths.employee360(widget.employeeId)'));
    expect(profile, contains('ApiPaths.employee360Register(widget.employeeId)'));
    expect(profile, contains("'type': widget.type"));
    expect(profile, contains("'page_size': _pageSize"));
    expect(profile, contains("const Tab(text: 'Stock Requests')"));
    expect(profile, contains("type: 'requests'"));
    expect(profile, contains("const Tab(text: 'Daily Reconciliation')"));
    expect(profile, contains("type: 'reconciliation'"));
    expect(profile, contains('RecordsList(rows: rows)'));
    expect(profile, contains('showDateRangePicker('));
  });

  test('Dashboard untouched and finance/GPS details are permission scoped', () {
    final profile = File('lib/screens/organization/employee_360_screen.dart')
        .readAsStringSync();
    final dashboard = File('lib/screens/home/home_screen.dart');
    final selfProfile = File('lib/screens/home/profile_screen.dart').readAsStringSync();
    expect(profile, contains("app.can('finance.accounting.view')"));
    expect(profile, contains("const Tab(text: 'Cash Responsibility')"));
    expect(profile, contains("const Tab(text: 'Person Ledger')"));
    expect(profile, contains("type: 'person_ledger'"));
    expect(profile, contains('complete_tagged_movement_history_not_visible_page'));
    expect(profile, contains('financial_accounts'));
    expect(profile, contains('stock_items'));
    expect(profile, contains('Sales INR and points are separate events'));
    expect(profile, contains("_Employee360TransitLedger(rows: ledgerData['entries'])"));
    expect(profile, contains("e['source_type'] == 'b2b_cash_remittance'"));
    expect(profile, contains("'EMPLOYEE_CASH_IN_TRANSIT'"));
    expect(profile, contains("app.can('workforce.gps.team.view')"));
    expect(profile, contains("data['read_only'] != true"));
    expect(profile, contains("data['dashboard_unchanged'] != true"));
    expect(profile, contains("int.tryParse('\${employee['id']}')"));
    expect(profile, contains('cash was deposited'));
    expect(profile, isNot(contains('paymentAccountId')));
    expect(dashboard.existsSync(), isTrue);
    expect(selfProfile, contains("import '../organization/employee_360_screen.dart';"));
    expect(selfProfile, contains("label: const Text('My Sales, Points & Stock')"));
  });
}
