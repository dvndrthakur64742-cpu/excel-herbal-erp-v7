import 'dart:io';

import 'package:excel_herbal_erp/widgets/v8_record_workspace.dart';
import 'package:excel_herbal_erp/widgets/v8_employee_identity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> customers() => [
  {'id': 101, 'name': 'Retailer A', 'mobile': '9876543210', 'status': 'active'},
  {'id': 102, 'name': 'Retailer B', 'mobile': '9876543211', 'status': 'inactive'},
];

void main() {
  for (final width in [360.0, 390.0, 768.0, 1366.0]) {
    testWidgets('V8 loaded-only records and employee identity at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.25)),
          child: child!,
        ),
        home: Scaffold(body: Column(children: [
          const V8EmployeeIdentityCard(employee: {
            'full_name': 'Employee A',
            'employee_code': 'EH-100',
            'designation_code': 'ASM',
            'status': 'active',
          }),
          Expanded(child: V8RecordWorkspace(
            title: 'Customer Accounts',
            subtitle: 'Authorised branch customer master',
            contextLabel: 'Test Branch',
            recordType: 'customer',
            rows: customers(),
          )),
        ])),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('v8-employee-identity')), findsOneWidget);
      expect(find.byKey(const ValueKey('v8-record-workspace')), findsOneWidget);
      expect(find.text('Employee A'), findsOneWidget);
      expect(find.text('Code EH-100'), findsOneWidget);
      expect(find.text('Customer Accounts'), findsOneWidget);
      expect(find.text('2 records loaded'), findsOneWidget);
      expect(find.text('Test Branch'), findsOneWidget);
      expect(find.byTooltip('Sort records'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Search preserves the canonical record list and does not rename count to branch total',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: V8RecordWorkspace(
        title: 'Expense Register',
        subtitle: 'Existing branch expense records',
        rows: customers(),
      ),
    )));
    await tester.enterText(find.byType(TextField).first, 'Retailer A');
    await tester.pumpAndSettle();
    expect(find.text('Retailer A'), findsWidgets);
    expect(find.text('Retailer B'), findsNothing);
    expect(find.text('2 records loaded'), findsOneWidget);
    expect(find.textContaining('global totals'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('Sales customer, Finance expenses, Employee registers share original data and actions', () {
    final sales = File('lib/screens/sales/sales_screen.dart').readAsStringSync();
    final expenses = File('lib/screens/finance/finance_expenses.dart').readAsStringSync();
    final finance = File('lib/screens/finance/finance_screen.dart').readAsStringSync();
    final profile = File('lib/screens/organization/employee_360_screen.dart').readAsStringSync();
    expect(sales, contains("title: 'Customer Accounts'"));
    expect(sales, contains("recordType: 'customer'"));
    expect(sales, contains('ApiPaths.customers'));
    expect(sales, contains('V8RecordWorkspace('));
    expect(expenses, contains("title: 'Expense Register'"));
    expect(expenses, contains("recordType: 'expense'"));
    expect(expenses, contains('onTap: _expenseAction'));
    expect(expenses, contains('ApiPaths.expenses'));
    expect(finance, contains("app.can('finance.bank_reconcile')"));
    expect(profile, contains('V8EmployeeIdentityCard(employee: employee)'));
    expect(profile, contains('V8RecordWorkspace('));
    expect(profile, contains("ApiPaths.employee360Register(widget.employeeId)"));
    expect(profile, contains("data['read_only'] != true"));
    expect(profile, contains("app.can('finance.accounting.view')"));
  });

  test('Expense amount and missing choices are validated inside the open form', () {
    final form = File('lib/screens/finance/finance_expenses.dart').readAsStringSync();
    expect(form, contains('String? formError;'));
    expect(form, contains('errorText: formError'));
    expect(form, contains('final parsed = double.tryParse(amount.text.trim());'));
    expect(form, contains('TransactionGuardrails.expense('));
    expect(form, contains('setLocal(() => formError = error);'));
    expect(form, contains('Navigator.pop(context, true);'));
    expect(form, contains('await api.post('));
    expect(form, contains('if (error != null) {'));
  });
}
