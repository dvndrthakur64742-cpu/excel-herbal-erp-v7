import 'dart:io';

import 'package:excel_herbal_erp/widgets/home_start_tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<HomeStartTask> tasks(
    Set<String> caps,
    Set<String> sections, {
    bool blocked = false,
  }) =>
      HomeStartTaskPlanner.recommend(
        can: caps.contains,
        sectionVisible: sections.contains,
        businessAccessBlocked: blocked,
      );

  test('field employee sees exactly three plain-English daily tasks', () {
    final planned = tasks(
      {'workforce.attendance.self', 'daily_order.self', 'sales.view'},
      {'home', 'my_work', 'sales'},
    );
    expect(planned.map((t) => t.id), [
      'attendance',
      'daily_create',
      'evening',
    ]);
    expect(planned.first.title, "Today's Duty");
    expect(planned.first.description, contains('automatic'));
  });

  test('manager reviews team workflow before lower-priority tasks', () {
    final planned = tasks(
      {
        'daily_order.approve',
        'inventory.transfer.receive',
        'sales.create',
        'workforce.attendance.self',
      },
      {'home', 'my_work', 'team', 'inventory', 'sales'},
    );
    expect(planned.map((t) => t.id), [
      'team_orders',
      'receive_stock',
      'counter_sale',
    ]);
  });

  test('permissions and projected navigation both restrict task entry', () {
    expect(
      tasks({'sales.create', 'daily_order.self'}, {'home'}),
      isEmpty,
    );
    expect(
      tasks(
        {'sales.create', 'daily_order.self'},
        {'home', 'sales', 'my_work'},
        blocked: true,
      ),
      isEmpty,
    );
    final admin = tasks(
      {'administration.access.manage', 'finance.expense.approve'},
      {'home', 'administration'},
    );
    expect(admin.map((t) => t.id), ['admin_access']);
  });

  testWidgets('one task is usable on a narrow phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.7),
            ),
            child: SingleChildScrollView(
              child: HomeStartTasks(
                tasks: const [
                  HomeStartTask(
                    id: 'daily_create',
                    title: 'Create Daily Order',
                    description: 'Choose products and quantities in PCS',
                    icon: Icons.shopping_cart_checkout,
                  ),
                ],
                onOpen: (task) => opened = task.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Create Daily Order'), findsOneWidget);
    await tester.tap(find.text('Open task'));
    expect(opened, 'daily_create');
  });

  test('daily order only submits after visible review and confirmation', () {
    final source = File(
      'lib/screens/my_work/my_work_daily_order.dart',
    ).readAsStringSync();
    expect(source, contains('Step 1 of 2'));
    expect(source, contains('Step 2 of 2'));
    expect(source, contains('Confirm Submit'));
    expect(source, contains('await persist(\'submit\')'));
    expect(source, contains('submittedOrderId'));
    expect(source, contains('PCS'));
    expect(source, contains('Save Draft'));
  });

  test('task-first navigation retains canonical owner, no duplicate menu', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();
    expect(shell, isNot(contains("_desktopTile(\n                    'quick_actions'")));
    expect(shell, contains("case 'team_orders':"));
    expect(shell, contains("case 'receive_stock':"));
    expect(shell, contains("case 'review_hr':"));
    expect(home, contains('HomeStartTasks('));
    expect(home, contains('openConnectedAction!(task.id)'));
  });
}
