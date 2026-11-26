import 'package:excel_herbal_erp/core/business_format.dart';
import 'package:excel_herbal_erp/core/counter_sale_preview.dart';
import 'package:excel_herbal_erp/widgets/counter_billing_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stock = <Map<String, dynamic>>[
    {'product_id': '1', 'product_name': 'Herbal A', 'quantity': '5', 'batch_key': '10'},
    {'product_id': '2', 'product_name': 'Herbal B', 'quantity': '8', 'batch_key': '0'},
  ];
  final products = <int, Map<String, dynamic>>{
    1: {'sale_price': '25.50'},
    2: {'sale_price': '100.00'},
  };
  CounterSalePreview review(List<String> quantities,
      {Map<int, Map<String, dynamic>>? prices}) =>
      CounterSalePreview.fromSelection(
        stock: stock, products: prices ?? products, quantities: quantities,
      );

  test('multiple products preserve batch and exact submission quantities', () {
    final result = review(['2', '3']);
    expect(result.error, isNull);
    expect(result.quantity, 5);
    expect(result.gross, 351);
    expect(result.lines, [
      {'product_id': '1', 'quantity': 2, 'batch_id': 10},
      {'product_id': '2', 'quantity': 3},
    ]);
  });

  test('invalid quantity, stock excess and missing price cannot give a payable total', () {
    for (final values in [
      ['6', '1'],
      ['1.5', '1'],
      ['bad', '1'],
      ['1'],
    ]) {
      final result = review(values);
      expect(result.error, isNotNull);
      expect(result.lines, isEmpty);
    }
    for (final rate in ['NaN', 'Infinity', '0', '-1']) {
      expect(review(['1', '0'], prices: {
        1: {'sale_price': rate}
      }).error, isNotNull);
    }
    expect(review(['', '0']).lines, isEmpty);
  });

  testWidgets('billing summary shows remaining and excess, never claims receipt',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final preview = review(['2', '3']);
    Future<void> show(double? paid) => tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.6)),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(
        child: CounterBillingSummary(preview: preview, paid: paid),
      )),
    ));
    await show(300);
    expect(find.text(BusinessFormat.money(351)), findsOneWidget);
    expect(find.text('Remaining cash: ${BusinessFormat.money(51)}'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await show(351);
    expect(find.text('Entered cash matches estimated total'), findsOneWidget);
    await show(360);
    expect(find.text('Excess cash: ${BusinessFormat.money(9)}'), findsOneWidget);
    await show(double.nan);
    expect(find.text('Check payment amount'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
