import 'dart:io';

import 'package:excel_herbal_erp/widgets/guided_workspace_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sections = [
    GuidedWorkspaceSection(
      title: 'Accounts & Books',
      description: 'View balances and entries.',
      icon: Icons.menu_book_outlined,
    ),
    GuidedWorkspaceSection(
      title: 'Expenses & Approvals',
      description: 'Review authorised expenses.',
      icon: Icons.receipt_long_outlined,
    ),
    GuidedWorkspaceSection(
      title: 'Branch Day Closing',
      description: 'Perform preflight before closing.',
      icon: Icons.fact_check_outlined,
    ),
  ];

  Widget screen({int initialIndex = 0}) => MaterialApp(
        home: DefaultTabController(
          length: sections.length,
          initialIndex: initialIndex,
          child: Scaffold(
            body: Column(
              children: [
                const GuidedWorkspaceSwitcher(
                  title: 'Choose your finance task',
                  sections: sections,
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      Center(child: Text('Accounts records')),
                      Center(child: Text('Expense records')),
                      Center(child: Text('Closing records')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  testWidgets('320px phone changes the real TabBarView without extra actions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Accounts records'), findsOneWidget);
    expect(find.byType(DropdownButton<int>), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expenses & Approvals').last);
    await tester.pumpAndSettle();
    expect(find.text('Expense records'), findsOneWidget);
    expect(find.text('Review authorised expenses.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop provides one chip per authorised section',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(screen(initialIndex: 2));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    expect(find.text('Closing records'), findsOneWidget);
    await tester.tap(find.text('Expenses & Approvals'));
    await tester.pumpAndSettle();
    expect(find.text('Expense records'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('team, finance and admin use only their capability-built tabs', () {
    final files = [
      'lib/screens/organization/team_screen.dart',
      'lib/screens/finance/finance_screen.dart',
      'lib/screens/administration/administration_screen.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, contains('GuidedWorkspaceSwitcher('));
      expect(source, contains('for (final tab in tabs)'));
      expect(source, contains('GuidedWorkspaceSection.forTab(tab.\$1)'));
      expect(source, contains('TabBarView(children:'));
      expect(source, isNot(contains('bottom: TabBar(')));
      expect(source, contains('app.can('));
    }
    final team = File(files.first).readAsStringSync();
    expect(team, contains("app.can('workforce.attendance.manage')"));
    expect(team, contains("app.can('organization.employee.view')"));
    final finance = File(files[1]).readAsStringSync();
    expect(finance, contains("app.can('finance.bank_reconcile')"));
    expect(finance, contains("app.can('finance.period.manage')"));
    final admin = File(files.last).readAsStringSync();
    expect(admin, contains("app.can('administration.access.manage')"));
    expect(admin, contains("app.can('administration.audit.view')"));
  });
}
