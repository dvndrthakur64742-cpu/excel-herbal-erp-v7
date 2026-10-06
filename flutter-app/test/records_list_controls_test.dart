import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/widgets/records_list.dart';

void main() {
  Future<void> showRecords(
    WidgetTester tester,
    List<Map<String, dynamic>> rows, {
    double width = 1366,
    String recordType = 'customer',
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RecordsList(rows: rows, recordType: recordType)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop table fills workspace without misleading selection',
      (tester) async {
    await showRecords(tester, [
      {'name': 'Ajay', 'mobile': '1234567890'},
    ]);
    expect(tester.getSize(find.byType(DataTable)).width, closeTo(1334, 1));
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byTooltip('View details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop tables prioritize business columns over raw extras',
      (tester) async {
    await showRecords(
      tester,
      [
        {
          'id': 17,
          'business_date': '2026-10-06',
          'employee_name': 'Asha Sharma',
          'branch_name': 'Mandi',
          'status': 'approved',
          'server_note': 'internal-looking extra',
          'created_at': '2026-10-06 09:00:00',
        },
      ],
      recordType: 'daily_order',
    );

    expect(find.text('Business Date'), findsOneWidget);
    expect(find.text('Employee'), findsOneWidget);
    expect(find.text('Branch'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Server Note'), findsNothing);
    expect(find.text('Created At'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product desktop table shows commercial decision columns first',
      (tester) async {
    await showRecords(
      tester,
      [
        {
          'product_name': 'Herbal Oil',
          'sku': 'HO-01',
          'mrp': 499,
          'sale_price': 449,
          'status': 'active',
          'uom': 'pcs',
        },
      ],
      recordType: 'product',
    );

    expect(find.text('Product'), findsOneWidget);
    expect(find.text('SKU'), findsOneWidget);
    expect(find.text('MRP'), findsOneWidget);
    expect(find.text('Sale Price'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('UOM'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search handles no matches and clearing restores records',
      (tester) async {
    await showRecords(tester, [
      {'name': 'Ajay', 'mobile': '1234567890'},
      {'name': 'Dev', 'mobile': '9876543210'},
    ]);
    await tester.enterText(find.byType(TextField), '9876');
    await tester.pumpAndSettle();
    expect(find.text('Dev'), findsOneWidget);
    expect(find.text('Ajay'), findsNothing);
    await tester.enterText(find.byType(TextField), 'missing customer');
    await tester.pumpAndSettle();
    expect(find.text('No matching records. Clear search or filters.'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Ajay'), findsOneWidget);
    expect(find.text('Dev'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('amount sorting is numeric and leaves source rows unchanged',
      (tester) async {
    final rows = [
      {'name': 'Ten', 'outstanding_amount': '10'},
      {'name': 'Two', 'outstanding_amount': '2'},
    ];
    await showRecords(tester, rows);
    await tester.tap(find.text('Outstanding'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Two')).dy,
        lessThan(tester.getTopLeft(find.text('Ten')).dy));
    expect(rows.first['name'], 'Ten');
    await tester.tap(find.text('Outstanding').first);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Ten')).dy,
        lessThan(tester.getTopLeft(find.text('Two')).dy));
  });

  testWidgets('pagination caps rendered rows and search resets page',
      (tester) async {
    await showRecords(tester, List.generate(26,
        (i) => {'name': 'Customer ${i + 1}', 'mobile': '900000${i + 1}'}));
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows.length, 25);
    expect(find.text('1–25 of 26 records'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Customer 26'), findsOneWidget);
    expect(find.text('26–26 of 26 records'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Customer 1');
    await tester.pumpAndSettle();
    expect(find.text('1–11 of 11 records'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile status filter preserves cards and clears correctly',
      (tester) async {
    await showRecords(tester, [
      {'name': 'Ajay', 'status': 'active'},
      {'name': 'Dev', 'status': 'inactive'},
    ], width: 360);
    await tester.tap(find.byTooltip('Filter by status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inactive').last);
    await tester.pumpAndSettle();
    expect(find.text('Ajay'), findsNothing);
    expect(find.text('Dev'), findsOneWidget);
    await tester.tap(find.byTooltip('Filter by status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    expect(find.text('Ajay'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
