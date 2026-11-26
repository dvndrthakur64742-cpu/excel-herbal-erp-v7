import 'package:excel_herbal_erp/core/prepaid_cart.dart';
import 'package:excel_herbal_erp/screens/sales/prepaid_cart_dialog.dart';
import 'package:excel_herbal_erp/widgets/search_choice_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stock = <Map<String, dynamic>>[
    {'product_id': '1', 'batch_key': '10', 'product_name': 'Herbal A',
      'batch_no': 'A-01', 'quantity': '6', 'uom': 'PCS'},
    {'product_id': '2', 'batch_key': '0', 'product_name': 'Herbal B',
      'quantity': '8', 'uom': 'PCS'},
    {'product_id': '1', 'batch_key': '11', 'product_name': 'Herbal A',
      'batch_no': 'A-02', 'quantity': '2', 'uom': 'PCS'},
  ];
  final products = <int, Map<String, dynamic>>{
    1: {'sale_price': '25.50', 'sku': 'SKU-A'},
    2: {'sale_price': '100.00', 'sku': 'SKU-B'},
  };

  test('cart preserves distinct product and batch lines for existing contract', () {
    final lines = PrepaidCart.lines(channel: 'b2c', stock: stock,
      quantities: {0: '2', 1: '3', 2: '1.5'});
    expect(lines, [
      {'product_id': 1, 'quantity': '2', 'batch_id': 10},
      {'product_id': 2, 'quantity': '3'},
      {'product_id': 1, 'quantity': '1.5', 'batch_id': 11},
    ]);
    expect(PrepaidCart.lineMinor(2550, '1.5'), 3825);
    expect(PrepaidCart.lineMinor(101, '1.5'), 152);
    expect(PrepaidCart.netMinor([5100, 30000], '10.00'), 34100);
  });

  test('rejects excess, invalid and split distributor selections', () {
    for (final selection in <Map<int, String>>[
      {}, {0: '7'}, {0: '0'}, {0: '1.1234'}, {4: '1'}
    ]) {
      expect(() => PrepaidCart.lines(channel: 'b2c', stock: stock,
        quantities: selection), throwsFormatException);
    }
    for (final selection in <Map<int, String>>[
      {0: '1.5'}, {0: '1', 2: '1'}
    ]) {
      expect(() => PrepaidCart.lines(channel: 'distributor', stock: stock,
        quantities: selection), throwsFormatException);
    }
    expect(PrepaidCart.lines(channel: 'distributor', stock: stock,
      quantities: {0: '2', 1: '3'}), hasLength(2));
    expect(() => PrepaidCart.netMinor([100], '1.00'), throwsFormatException);
    expect(() => PrepaidCart.netMinor([100], '0.001'), throwsFormatException);
    expect(() => PrepaidCart.lineMinor(999999999999, '999999'), throwsFormatException);
  });

  testWidgets('search preserves stable identifier after filtering', (tester) async {
    int? selected;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        selected = await showDialog<int>(context: context,
          builder: (_) => const SearchChoiceDialog(title: 'Pick', choices: [
            SearchChoice(7, 'Alpha', 'Batch AA'),
            SearchChoice(23, 'Beta', 'Batch BB', search: ['B-SKU']),
          ]));
      }, child: const Text('Open'))),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'b-sku');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(selected, 23);
  });

  testWidgets('two products are reviewed before a payload can be returned', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Map<String, dynamic>? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        result = await showDialog<Map<String, dynamic>>(context: context,
          builder: (_) => PrepaidCartDialog(
            branch: 1, branchName: 'Test branch', stock: stock,
            customers: const [], products: products,
            quote: (product, quantity) async => throw StateError('Unexpected distributor quote'),
          ));
      }, child: const Text('Open cart'))),
    )));
    await tester.tap(find.text('Open cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'A-01');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Herbal A'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add product'));
    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'SKU-B');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Herbal B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review order'));
    await tester.pumpAndSettle();
    expect(find.text('Review prepaid order'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Create order'));
    await tester.pumpAndSettle();
    expect(result?['lines'], hasLength(2));
    expect(result?['channel'], 'b2c');
    expect(tester.takeException(), isNull);
  });
}
