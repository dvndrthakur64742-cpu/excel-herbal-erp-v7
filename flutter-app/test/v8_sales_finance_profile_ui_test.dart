import 'dart:io';

import 'package:excel_herbal_erp/widgets/v8_module_banner.dart';
import 'package:excel_herbal_erp/screens/organization/employee_360_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 390.0, 768.0, 1366.0]) {
    testWidgets('V8 Sales, Finance and Employee headers render at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.35)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(
          child: Column(children: const [
            V8ModuleBanner(
              eyebrow: 'Sales operations / ERP V8',
              title: 'Sales & Customers',
              description: 'Counter billing, customer accounts and collections.',
              icon: Icons.point_of_sale_outlined,
              context: ['Test Branch', 'Business date 2026-10-24'],
            ),
            V8ModuleBanner(
              eyebrow: 'Finance controls / ERP V8',
              title: 'Finance & Accounts',
              description: 'Books, expenses and accounting periods.',
              icon: Icons.account_balance_outlined,
              context: ['Test Branch', 'Business date 2026-10-24'],
            ),
            V8ModuleBanner(
              eyebrow: 'Employee 360 / ERP V8',
              title: 'Employee A',
              description: 'Linked work records. Read-only.',
              icon: Icons.badge_outlined,
              context: ['2026-10-01 to 2026-10-24', 'Posted records only'],
            ),
          ]),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('v8-module-banner')), findsNWidgets(3));
      expect(find.text('Sales & Customers'), findsOneWidget);
      expect(find.text('Finance & Accounts'), findsOneWidget);
      expect(find.text('Employee A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('New visuals preserve old authorised Sales and Finance mutation paths', () {
    final sales = File('lib/screens/sales/sales_screen.dart').readAsStringSync();
    final finance = File('lib/screens/finance/finance_screen.dart').readAsStringSync();
    expect(sales, contains('V8ModuleBanner('));
    expect(sales, contains("app.can('sales.create')"));
    expect(sales, contains("app.can('sales.receipt.create')"));
    expect(sales, contains('ModuleActionPanel('));
    expect(sales, contains('ApiPaths.customers'));
    expect(sales, contains('onPressed: app.currentBranchId == null'));
    expect(finance, contains('V8ModuleBanner('));
    expect(finance, contains("app.can('finance.bank_reconcile')"));
    expect(finance, contains("app.can('finance.period.manage')"));
    expect(finance, contains("if (widget.initialAction == 'expense') await _expense()"));
    expect(finance, contains('TabBarView(children:'));
    expect(finance, contains('ModuleMessageBanner(message: message!)'));
  });

  test('Profile keeps server identity, separate finance/GPS scopes and no write', () {
    final src = File('lib/screens/organization/employee_360_screen.dart')
        .readAsStringSync();
    final groups = File('lib/screens/organization/employee_360_workspace.dart')
        .readAsStringSync();
    expect(src, contains('V8ModuleBanner('));
    expect(src, contains("data['read_only'] != true"));
    expect(src, contains("data['dashboard_unchanged'] != true"));
    expect(src, contains("app.can('finance.accounting.view')"));
    expect(src, contains("app.can('workforce.gps.team.view')"));
    expect(src, contains('if (financeVisible) const Tab(text:'));
    expect(src, contains('if (showGps) const Tab(text:'));
    expect(groups, contains('v8-profile-navigation'));
    expect(groups, contains('selectedTileColor: ExcelBrand.primarySoft'));
    expect(const Employee360Workspace(
      tabs: [Tab(text: 'Summary')],
      child: SizedBox.shrink(),
    ), isA<Employee360Workspace>());
  });
}
