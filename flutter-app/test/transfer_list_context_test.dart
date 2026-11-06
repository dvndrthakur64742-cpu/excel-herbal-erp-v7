import 'package:excel_herbal_erp/core/transfer_list_presentation.dart';
import 'package:excel_herbal_erp/widgets/records_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const branches = <Map<String, dynamic>>[
    {'id': 1, 'name': 'Head Office'},
    {'id': 2, 'name': 'Mandi'},
  ];

  test('single-line transfer shows branch names and unit-safe quantity', () {
    final source = <String, dynamic>{
      'id': 38, 'source_branch_id': 1, 'destination_branch_id': 2,
      'line_count': '1', 'single_quantity': '4.000', 'single_uom': 'PCS',
      'status': 'in_transit',
    };
    final row = TransferListPresentation.row(source, branches);
    expect(row['transfer_number'], 'Transfer #38');
    expect(row['source_branch_name'], 'Head Office');
    expect(row['destination_branch_name'], 'Mandi');
    expect(row['items_summary'], '4 PCS');
    expect(row['status'], 'in_transit');
    expect(row['id'], 38);
    expect(source.containsKey('items_summary'), isFalse);
  });

  test('multiple lines never sum quantities across incompatible units', () {
    final row = TransferListPresentation.row({
      'id': 19, 'source_branch_id': 1, 'destination_branch_id': 4,
      'destination_branch_name': 'Kullu',
      'line_count': 3, 'single_quantity': 900, 'single_uom': 'PCS',
      'status': 'packed',
    }, branches);
    expect(row['items_summary'], '3 line items');
    expect(row['destination_branch_name'], 'Kullu');
  });

  test('legacy API without summary does not invent stock quantities', () {
    final row = TransferListPresentation.row({
      'id': 5, 'source_branch_id': 1, 'destination_branch_id': 99,
      'status': 'draft',
    }, branches);
    expect(row['items_summary'], 'View items');
    expect(row['destination_branch_name'], 'Branch #99');
  });

  testWidgets('transfer table prioritizes number, source, destination and items',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1250, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final row = TransferListPresentation.row({
      'id': 38, 'source_branch_id': 1, 'destination_branch_id': 2,
      'line_count': 1, 'single_quantity': 4, 'single_uom': 'PCS',
      'status': 'in_transit',
      'created_at': '2026-11-06 07:30:00',
    }, branches);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RecordsList(
        recordType: 'stock_transfer',
        titleKeys: const ['transfer_number'],
        rows: [row],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Transfer #38'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Items'), findsOneWidget);
    expect(find.text('Head Office'), findsOneWidget);
    expect(find.text('Mandi'), findsOneWidget);
    expect(find.text('4 PCS'), findsOneWidget);
    expect(find.text('Created At'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transfer mobile card presents branches and unit/item summary',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final row = TransferListPresentation.row({
      'id': 38, 'source_branch_id': 1, 'destination_branch_id': 2,
      'line_count': 1, 'single_quantity': 4, 'single_uom': 'PCS',
      'status': 'in_transit',
    }, branches);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RecordsList(
        recordType: 'stock_transfer',
        titleKeys: const ['transfer_number'],
        rows: [row],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Transfer #38'), findsOneWidget);
    expect(find.text('Head Office'), findsOneWidget);
    expect(find.text('Mandi'), findsOneWidget);
    expect(find.text('4 PCS'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
