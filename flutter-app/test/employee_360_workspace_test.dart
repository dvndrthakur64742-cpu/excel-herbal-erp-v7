import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/screens/organization/employee_360_workspace.dart';

const labels = [
  'Summary',
  'Sales',
  'Stock',
  'Stock Requests',
  'Daily Reconciliation',
  'Attendance',
  'Ledger',
  'Person Ledger',
  'Cash Responsibility',
  'Cash Control',
  'Finance Review',
  'GPS Route',
];

Widget workspace({
  int initial = 0,
  bool finance = true,
  bool gps = true,
  double scale = 1,
}) {
  final permitted = labels
      .where(
        (label) =>
            (finance || !labels.sublist(6, 11).contains(label)) &&
            (gps || label != 'GPS Route'),
      )
      .toList();
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: DefaultTabController(
      key: ValueKey('$finance-$gps'),
      length: permitted.length,
      initialIndex: initial,
      child: Scaffold(
        body: Employee360Workspace(
          tabs: [for (final label in permitted) Tab(text: label)],
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final label in permitted)
                Builder(
                  builder: (context) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Records: $label'),
                        if (label == 'Finance Review')
                          TextButton(
                            onPressed: () => DefaultTabController.of(
                              context,
                            ).animateTo(permitted.indexOf('Person Ledger')),
                            child: const Text('Open linked ledger'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Desktop groups use original registers and linked ledger', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(workspace());
    expect(find.byType(TabBar), findsNothing);
    for (final group in [
      'Overview',
      'Operations',
      'Finance',
      'People',
      'GPS',
    ]) {
      expect(find.text(group), findsOneWidget);
    }
    await tester.tap(find.text('Operations'));
    await tester.pumpAndSettle();
    expect(find.text('Records: Sales'), findsOneWidget);
    await tester.tap(find.text('Stock Requests'));
    await tester.pumpAndSettle();
    expect(find.text('Records: Stock Requests'), findsOneWidget);
    await tester.tap(find.text('Finance'));
    await tester.pumpAndSettle();
    expect(find.text('Records: Finance Review'), findsOneWidget);
    await tester.tap(find.text('Open linked ledger'));
    await tester.pumpAndSettle();
    expect(find.text('Records: Person Ledger'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('employee360-view-7')))
          .selected,
      isTrue,
    );
    expect(find.text('Journal Lines'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [360.0, 390.0, 768.0, 840.0, 1366.0]) {
    testWidgets('Finance deep link and resize at $width with large text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(workspace(initial: 10, scale: 1.5));
      await tester.pumpAndSettle();
      expect(find.text('Records: Finance Review'), findsOneWidget);
      await tester.tap(find.text('Open linked ledger'));
      await tester.pumpAndSettle();
      expect(find.text('Records: Person Ledger'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      await tester.pumpAndSettle();
      expect(find.text('Records: Person Ledger'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Mobile selectors reach records without horizontal swiping', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(workspace());
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Operations').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily Reconciliation').last);
    await tester.pumpAndSettle();
    expect(find.text('Records: Daily Reconciliation'), findsOneWidget);
    await tester.drag(find.byType(TabBarView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Records: Daily Reconciliation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Permission removal drops finance and GPS navigation and contents',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(workspace(initial: 10));
      await tester.pumpAndSettle();
      await tester.pumpWidget(workspace(finance: false, gps: false));
      await tester.pumpAndSettle();
      expect(find.text('Finance'), findsNothing);
      expect(find.text('GPS'), findsNothing);
      expect(find.text('Records: Finance Review'), findsNothing);
      expect(find.text('Records: Summary'), findsOneWidget);
      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(find.text('Records: Attendance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
