import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/widgets/v8_daily_order_board.dart';
import 'package:excel_herbal_erp/widgets/v8_inventory_banner.dart';

Map<String, dynamic> cycle(int id, String status, {String additional = ''}) =>
    <String, dynamic>{
      'id': id,
      'status': status,
      'additional_request_status': additional,
    };

void main() {
  test('V8 workboard stages never mistake issued/approval for a posted closing', () {
    final rows = <Map<String, dynamic>>[
      cycle(1, 'morning_draft'),
      cycle(2, 'stock_requested'),
      cycle(3, 'approved'),
      cycle(4, 'issued'),
      cycle(5, 'issued', additional: 'submitted'),
      cycle(6, 'issued', additional: 'approved'),
      cycle(7, 'evening_draft'),
      cycle(8, 'evening_submitted'),
      cycle(9, 'completed'),
      cycle(10, 'rejected'),
      cycle(11, 'unknown_server_status'),
    ];
    expect(V8DailyOrderStages.count(rows, 'all'), 11);
    expect(V8DailyOrderStages.count(rows, 'draft'), 1);
    expect(V8DailyOrderStages.count(rows, 'approval'), 2);
    expect(V8DailyOrderStages.count(rows, 'issue'), 2);
    expect(V8DailyOrderStages.count(rows, 'field'), 2);
    expect(V8DailyOrderStages.count(rows, 'review'), 1);
    expect(V8DailyOrderStages.count(rows, 'closed'), 2);
    expect(V8DailyOrderStages.stage(rows.last), '');
    expect(V8DailyOrderStages.visible(rows, 'untrusted'), isEmpty);
    expect(() => V8DailyOrderStages.visible(rows, 'all').clear(),
        throwsUnsupportedError);
  });

  testWidgets('V8 stage filters show loaded-only counts and trigger selection',
      (tester) async {
    var selected = 'all';
    final rows = <Map<String, dynamic>>[
      cycle(1, 'stock_requested'), cycle(2, 'issued')];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: V8DailyOrderBoard(
        rows: rows, selectedStage: selected,
        onStageChanged: (value) => selected = value,
      )),
    )));
    expect(find.byKey(const ValueKey('v8-daily-workboard')), findsOneWidget);
    expect(find.text('2 loaded records · authorised scope only'), findsOneWidget);
    expect(find.text('Approval  1'), findsOneWidget);
    expect(find.text('Field Closing  1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('v8-daily-filter-approval')));
    expect(selected, 'approval');
  });

  testWidgets('V8 original Daily Order card preserves open and action callbacks',
      (tester) async {
    var opened = 0;
    var closed = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SizedBox(height: 230, child: V8DailyOrderCard(
        id: 51, employee: 'Employee A', branch: 'Authorised Branch',
        businessDate: '2026-10-24',
        statusBadge: const Text('Issued · Evening Pending'),
        onOpen: () => opened++,
        action: OutlinedButton(
          onPressed: () => closed++, child: const Text('Start Closing')),
      )),
    )));
    expect(find.text('ORDER #51'), findsOneWidget);
    expect(find.text('Employee A'), findsOneWidget);
    await tester.tap(find.text('Employee A'));
    expect(opened, 1);
    await tester.tap(find.text('Start Closing'));
    expect(closed, 1);
  });

  testWidgets('Inventory V8 banner is scoped to actual branch and business date',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: V8InventoryBanner(
        branch: 'Branch A', businessDate: '2026-10-24'),
    )));
    expect(find.byKey(const ValueKey('v8-inventory-banner')), findsOneWidget);
    expect(find.text('Branch A'), findsOneWidget);
    expect(find.text('2026-10-24'), findsOneWidget);
    expect(find.textContaining('total stock'), findsNothing);
  });
}
