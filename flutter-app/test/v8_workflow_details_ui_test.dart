import 'dart:io';

import 'package:excel_herbal_erp/widgets/v8_employee_overview.dart';
import 'package:excel_herbal_erp/widgets/v8_sale_stock_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0, 768.0]) {
    testWidgets('Counter Sale product quantity stays usable at ${width}px',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final qty = TextEditingController();
      addTearDown(qty.dispose);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.25)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(
          child: V8SaleStockLine(
            productName: 'Excel Herbal Tea',
            batchLabel: 'Batch A',
            availableText: '25 PCS',
            salePriceText: '300',
            batchModeText: 'Optional',
            quantityController: qty,
          ),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('v8-sale-stock-line')), findsOneWidget);
      expect(find.text('Excel Herbal Tea'), findsOneWidget);
      expect(find.text('Qty'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '2');
      expect(qty.text, '2');
    });
  }

  for (final width in [360.0, 390.0, 768.0, 1366.0]) {
    testWidgets('Employee 360 monthly sales and stock render at ${width}px',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final months = <Map<String, dynamic>>[
        {'month': '2026-10', 'sales_amount': '12500.00',
          'points': '320', 'days_present': 21},
        {'month': '2026-09', 'sales_amount': '18000.00',
          'points': '450', 'days_present': 24},
      ];
      final stock = <Map<String, dynamic>>[
        {'product_id': 25, 'batch_key': 11,
          'product_name': 'Excel Herbal Tea', 'branch_id': 1,
          'quantity': 8},
      ];
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.2)),
          child: child!,
        ),
        home: Scaffold(body: V8EmployeeOverview(
          employee: const {'full_name': 'Employee A',
            'employee_code': 'EH-101', 'designation_code': 'ASM'},
          months: months,
          stock: stock,
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('v8-employee-overview')), findsOneWidget);
      expect(find.text('Employee A'), findsOneWidget);
      expect(find.text('Monthly Sales & Points'), findsOneWidget);
      expect(find.text('12500.00'), findsWidgets);
      expect(find.text('320'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Employee-held stock'), findsOneWidget);
      expect(find.text('8 PCS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('Finance ledger and expense-head form failures remain in dialogs', () {
    final source = File('lib/screens/finance/finance_books.dart').readAsStringSync();
    expect(source, contains("title: 'Trial Balance'"));
    expect(source, contains("recordType: 'trial_balance'"));
    expect(source, contains('V8RecordWorkspace('));
    expect(source, contains('String? ledgerFormError;'));
    expect(source, contains('String? headFormError;'));
    expect(source, contains('ledgerFormError ='));
    expect(source, contains('headFormError ='));
    expect(source, contains('if (codeText.isEmpty || nameText.isEmpty)'));
    expect(source, contains('accountId == null'));
    expect(source, contains('ApiPaths.financeAccounts'));
    expect(source, contains('ApiPaths.expenseHeads'));
  });

  test('Original sale and Employee 360 API security contracts remain', () {
    final sale = File('lib/screens/sales/sales_screen.dart').readAsStringSync();
    final profile = File('lib/screens/organization/employee_360_screen.dart')
        .readAsStringSync();
    final overview = File('lib/widgets/v8_employee_overview.dart').readAsStringSync();
    expect(sale, contains('V8SaleStockLine('));
    expect(sale, contains('WholePcs.parseOrZero(qty[i]!.text)'));
    expect(sale, contains('TransactionGuardrails.counterSale('));
    expect(sale, contains('ApiPaths.counterSale'));
    expect(sale, contains('ApiPaths.customerReceipt'));
    expect(profile, contains('V8EmployeeOverview('));
    expect(profile, contains("profile['monthly_summary']"));
    expect(profile, contains("profile['employee_stock']"));
    expect(profile, contains("app.can('finance.accounting.view')"));
    expect(profile, contains("app.can('workforce.gps.team.view')"));
    expect(overview, contains('Cash remittance is not independently verified'));
    expect(overview, contains('No employee outstanding balance is inferred.'));
  });
}
