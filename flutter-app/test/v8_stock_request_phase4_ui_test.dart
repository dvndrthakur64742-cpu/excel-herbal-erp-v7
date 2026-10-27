import 'dart:io';

import 'package:excel_herbal_erp/core/whole_pcs.dart';
import 'package:excel_herbal_erp/theme/excel_brand.dart';
import 'package:excel_herbal_erp/widgets/v8_stock_request_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0, 1366.0]) {
    testWidgets('Stock Request form controls fit ${width}px at 135% text',
        (tester) async {
      final quantity = TextEditingController();
      addTearDown(quantity.dispose);
      await tester.binding.setSurfaceSize(Size(width, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var selectedOnly = false;
      await tester.pumpWidget(MaterialApp(
        theme: ExcelBrand.lightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.35),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                const V8StockRequestSteps(),
                const SizedBox(height: 10),
                V8StockSelectionBar(
                  summary: '2 products · 25 PCS selected',
                  selectedOnly: false,
                  enabled: true,
                  onSelected: (value) => selectedOnly = value,
                ),
                const SizedBox(height: 10),
                V8StockRequestProductLine(
                  name: 'Premium Herbal Hair Oil - Large Bottle',
                  sku: 'EH-REAL-01',
                  commercial: '₹350 · 10 pts',
                  quantity: quantity,
                  selectedQuantity: 0,
                  enabled: true,
                  onChanged: (_) {},
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('v8-stock-request-steps')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('v8-stock-selection-bar')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('v8-stock-product-line')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('v8-stock-selected-only')));
      expect(selectedOnly, isTrue);
      await tester.enterText(find.byType(TextField), '12');
      expect(WholePcs.parse(quantity.text), 12);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Stock Request preserves whole-PCS entry filtering',
      (tester) async {
    final quantity = TextEditingController();
    addTearDown(quantity.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: V8StockRequestProductLine(
        name: 'Product A',
        sku: 'SKU-A',
        commercial: '',
        quantity: quantity,
        selectedQuantity: 0,
        enabled: true,
        onChanged: (_) {},
      ),
    )));
    await tester.enterText(find.byType(TextField), '1.5');
    expect(quantity.text, isNot(contains('.')));
    expect(tester.takeException(), isNull);
  });

  test('Phase 4 UI retains the original request and issue API guards', () {
    final source = File('lib/screens/my_work/my_work_daily_order.dart')
        .readAsStringSync();
    expect(source, contains('V8StockRequestSteps('));
    expect(source, contains('V8StockSelectionBar('));
    expect(source, contains('V8StockRequestProductLine('));
    expect(source, contains('WholePcs.parseOrZero'));
    expect(source, contains('ApiPaths.dailySubmit('));
    expect(source, contains('ApiPaths.dailyIssuePreflight('));
    expect(source, contains('DailyOrderWorkflow.stockIssueReady('));
    expect(source, contains('ApiPaths.dailyIssue('));
  });
}
