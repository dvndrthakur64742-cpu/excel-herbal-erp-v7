import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/evening_order_selection.dart';
import 'package:excel_herbal_erp/widgets/evening_order_picker.dart';

Map<String, dynamic> order(int id, {
  int employee = 101,
  int branch = 1,
  String status = 'issued',
  String date = '2026-10-24',
}) => {
  'id': id, 'employee_id': employee, 'employee_name': 'Employee $employee',
  'employee_code': 'EH-$employee', 'branch_id': branch,
  'branch_name': 'Test Branch', 'status': status, 'business_date': date,
};

List<Map<String, dynamic>> select(List<Map<String, dynamic>> rows, {
  bool self = true, bool others = false, int? branch = 1, int? employee = 101,
}) => EveningOrderSelection.candidates(
  rows: rows, businessDate: '2026-10-24', branchId: branch,
  actorEmployeeId: employee, selfAllowed: self, othersAllowed: others,
);

void main() {
  test('own evening shortcut cannot choose another employee or branch', () {
    final result = select([
      order(5), order(7, employee: 102), order(9, branch: 2),
      order(10, status: 'completed'), order(11, date: '2026-10-23'),
      order(12, status: 'evening_draft'),
    ]);
    expect(result.map((r) => r['id']), [12, 5]);
    expect(() => result.clear(), throwsUnsupportedError);
  });

  test('ASM may review multiple orders but only in explicitly chosen branch', () {
    final result = select([
      order(5), order(7, employee: 102), order(9, branch: 2),
      order(12, status: 'evening_draft'),
    ], self: false, others: true);
    expect(result.map((r) => r['id']), [12, 7, 5]);
    expect(select([order(7, employee: 102)], branch: null), isEmpty);
  });

  test('stale role, employee, business day or branch fail closed on return', () {
    final row = order(5);
    bool recheck({bool self = true, bool others = false, int? branch = 1,
        int? employee = 101, String date = '2026-10-24'}) =>
        EveningOrderSelection.remainsAllowed(
          selected: row, businessDate: date, branchId: branch,
          actorEmployeeId: employee, selfAllowed: self, othersAllowed: others);
    expect(recheck(), isTrue);
    expect(recheck(self: false), isFalse);
    expect(recheck(branch: 2), isFalse);
    expect(recheck(employee: 102), isFalse);
    expect(recheck(date: '2026-10-25'), isFalse);
  });

  test('duplicate or malformed eligible original rows fail closed', () {
    expect(() => select([order(3), order(3)]), throwsFormatException);
    expect(() => select([order(3, employee: 0)]), throwsFormatException);
    expect(() => select([order(0)]), throwsFormatException);
    expect(select([order(3)], self: false, others: false), isEmpty);
  });

  testWidgets('multi-order picker shows employee and status and returns exact ID',
      (tester) async {
    int? chosen;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => ElevatedButton(
        onPressed: () async {
          chosen = await showDialog<int>(context: context,
              builder: (_) => EveningOrderPicker(candidates: [
                order(7, employee: 102), order(5),
              ]));
        },
        child: const Text('Start closing'),
      )),
    )));
    await tester.tap(find.text('Start closing'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Evening Closing'), findsOneWidget);
    expect(find.text('#7 · Employee 102'), findsOneWidget);
    expect(find.text('#5 · Employee 101'), findsOneWidget);
    expect(find.textContaining('Issued · Evening Pending'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('evening-order-5')));
    await tester.pumpAndSettle();
    expect(chosen, 5);
  });

  testWidgets('closing selection can be cancelled without opening a cycle',
      (tester) async {
    int? chosen = 99;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => ElevatedButton(
        onPressed: () async {
          chosen = await showDialog<int>(context: context,
              builder: (_) => EveningOrderPicker(candidates: [
                order(7, employee: 102), order(5),
              ]));
        },
        child: const Text('Start closing'),
      )),
    )));
    await tester.tap(find.text('Start closing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
  });
  testWidgets('picker filters by employee code and exact order ID without selecting others',
      (tester) async {
    int? chosen;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => ElevatedButton(
        onPressed: () async {
          chosen = await showDialog<int>(context: context,
              builder: (_) => EveningOrderPicker(candidates: [
                order(12, employee: 101),
                order(24, employee: 102, status: 'evening_draft'),
                order(36, employee: 103),
              ]));
        },
        child: const Text('Open chooser'),
      )),
    )));
    await tester.tap(find.text('Open chooser'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 3 of 3 eligible orders'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('evening-order-search')), 'EH-102');
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 3 eligible orders'), findsOneWidget);
    expect(find.byKey(const ValueKey('evening-order-24')), findsOneWidget);
    expect(find.byKey(const ValueKey('evening-order-12')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('evening-order-search')), 'not-listed');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('evening-order-no-results')), findsOneWidget);
    expect(chosen, isNull);
    await tester.tap(find.byTooltip('Clear order search'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 3 of 3 eligible orders'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('evening-order-search')), '#24');
    await tester.pumpAndSettle();
    expect(find.textContaining('Evening Draft'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('evening-order-24')));
    await tester.pumpAndSettle();
    expect(chosen, 24);
  });

  testWidgets('picker remains usable on compact screen and soft keyboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => ElevatedButton(
        onPressed: () => showDialog<int>(context: context,
          builder: (_) => EveningOrderPicker(candidates: [
            order(5), order(6, employee: 102), order(7, employee: 103),
          ])),
        child: const Text('Pick order'),
      )),
    )));
    await tester.tap(find.text('Pick order'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('v8-evening-order-picker')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(
        find.byKey(const ValueKey('evening-order-search')), '103');
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 3 eligible orders'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('filtering and picking never calls server or grants new branch access', () {
    final selected = select([
      order(10, employee: 101), order(11, employee: 102),
      order(12, branch: 2),
    ]);
    expect(selected.length, 1);
    expect(selected.single['id'], 10);
    expect(EveningOrderSelection.remainsAllowed(
      selected: selected.single, businessDate: '2026-10-24', branchId: 2,
      actorEmployeeId: 101, selfAllowed: true, othersAllowed: false,
    ), isFalse);
  });

}
