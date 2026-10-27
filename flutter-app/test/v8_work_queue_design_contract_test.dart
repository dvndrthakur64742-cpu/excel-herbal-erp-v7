import 'dart:io';
import 'package:excel_herbal_erp/theme/excel_brand.dart';
import 'package:excel_herbal_erp/widgets/v8_daily_order_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0, 1366.0]) {
    testWidgets('responsive Daily Order queue and filters at ${width}', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 880));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var chosen = 'all';
      await tester.pumpWidget(MaterialApp(
        theme: ExcelBrand.lightTheme(),
        home: Scaffold(body: SingleChildScrollView(
          child: V8DailyOrderBoard(
            selectedStage: chosen,
            rows: const [
              {'id': 10, 'status': 'morning_draft'},
              {'id': 11, 'status': 'stock_requested'},
              {'id': 12, 'status': 'approved'},
            ],
            onStageChanged: (value) => chosen = value,
          ),
        )),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Daily work pipeline'), findsOneWidget);
      expect(find.byKey(const ValueKey('v8-daily-stage-count')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('v8-daily-filter-approval')));
      await tester.pumpAndSettle();
      expect(chosen, 'approval');
      expect(tester.takeException(), isNull);
    });
  }

  test('review queue is a redesigned role-scoped presentation only', () {
    final source = File('lib/screens/home/enterprise_hub_screen.dart')
      .readAsStringSync();
    expect(source, contains('Your approval queue'));
    expect(source, contains("ValueKey('v8-approvals-summary')"));
    expect(source, contains('Review details'));
    expect(source, contains('onAction(item, false)'));
    expect(source, contains('onAction(item, true)'));
    expect(source, contains('_approvalVisible(app)'));
    expect(source, contains('onOpen(item)'));
  });

  test('My Work retains branch permissions and original API actions', () {
    final overview = File('lib/screens/my_work/my_work_daily_overview.dart')
      .readAsStringSync();
    final screen = File('lib/screens/my_work/my_work_screen.dart')
      .readAsStringSync();
    expect(overview, contains("ValueKey('v8-new-daily-order')"));
    expect(overview, contains("app.can('daily_order.self')"));
    expect(overview, contains("_MyWorkDaily(this)._newDailyOrder"));
    expect(screen, contains('BranchSelector()'));
    expect(screen, contains("ValueKey('v8-my-work-sections')"));
    expect(screen, contains('_daily()'));
  });
}
