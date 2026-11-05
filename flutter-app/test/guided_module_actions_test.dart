import 'dart:io';

import 'package:excel_herbal_erp/widgets/guided_action_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone shows only primary task; other tasks remain reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var primaryOpened = 0;
    var secondaryOpened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: SingleChildScrollView(
            child: GuidedActionPanel(
              title: 'What would you like to do?',
              subtitle: 'Select a permitted task.',
              actions: [
                GuidedAction(
                  id: 'purchase',
                  title: 'New Purchase Bill',
                  description: 'Enter an authorised supplier bill.',
                  icon: Icons.receipt_long_outlined,
                  primary: true,
                  onOpen: () => primaryOpened++,
                ),
                GuidedAction(
                  id: 'supplier',
                  title: 'Add Supplier',
                  description: 'Register a supplier in the shared master.',
                  icon: Icons.person_add_outlined,
                  onOpen: () => secondaryOpened++,
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('New Purchase Bill'), findsOneWidget);
    expect(find.text('More tasks (1)'), findsOneWidget);
    await tester.tap(find.text('Start'));
    expect(primaryOpened, 1);
    await tester.ensureVisible(find.text('More tasks (1)'));
    await tester.tap(find.text('More tasks (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Add Supplier'), findsOneWidget);
    await tester.ensureVisible(find.text('Open'));
    await tester.tap(find.text('Open'));
    expect(secondaryOpened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branch-required task disables its actual launcher',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GuidedActionPanel(
          title: 'Inventory',
          subtitle: 'Choose authorised stock task.',
          actions: [
            GuidedAction(
              id: 'transfer',
              title: 'Transfer Stock',
              description: 'Move stock between branches.',
              icon: Icons.swap_horiz,
              enabled: false,
              primary: true,
              onOpen: () => calls++,
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Select an authorised branch to continue.'),
        findsOneWidget);
    expect(calls, 0);
  });

  test('sales purchase and inventory preserve canonical permission gates', () {
    final sales = File('lib/screens/sales/sales_screen.dart').readAsStringSync();
    final purchase =
        File('lib/screens/purchase/purchase_screen.dart').readAsStringSync();
    final inventory =
        File('lib/screens/inventory/inventory_screen.dart').readAsStringSync();
    for (final source in [sales, purchase, inventory]) {
      expect(source, contains('GuidedActionPanel('));
      expect(source, contains('final branchReady = app.currentBranchId != null;'));
      expect(source, contains('enabled: branchReady'));
      expect(source, contains('What would you like to do?'));
    }
    expect(sales, contains("app.can('sales.receipt.create')"));
    expect(sales, contains('onOpen: _receipt'));
    expect(sales, contains("builder: (_) => const PrepaidOrdersScreen()"));
    expect(purchase, contains("app.can('finance.supplier_payment.create')"));
    expect(purchase, contains('onOpen: _payBill'));
    expect(inventory, contains("app.can('inventory.adjustment.create')"));
    expect(inventory, contains('onOpen: _createQuarantine'));
  });
}
