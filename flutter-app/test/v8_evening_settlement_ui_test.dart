import 'dart:io';

import 'package:excel_herbal_erp/widgets/v8_evening_closing_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0, 768.0, 1366.0]) {
    testWidgets('Evening Closing return and wholesale inputs fit ${width}px',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final returned = TextEditingController();
      final wholesale = TextEditingController(text: '0');
      final rate = TextEditingController(text: '40.00');
      addTearDown(returned.dispose);
      addTearDown(wholesale.dispose);
      addTearDown(rate.dispose);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.25)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, refresh) {
                final ret = int.tryParse(returned.text) ?? 0;
                final wh = int.tryParse(wholesale.text) ?? 0;
                return V8EveningClosingLine(
                  productName: 'Excel Herbal Tea · Extra Strong',
                  issuedLabel: '12',
                  soldLabel: '${12 - ret - wh}',
                  retailRateLabel: '80.00',
                  wholesaleEnabled: true,
                  wholesaleQuantity: wh,
                  overIssued: ret + wh > 12,
                  returnController: returned,
                  wholesaleController: wholesale,
                  wholesaleRateController: rate,
                  onQuantityChanged: () => refresh(() {}),
                );
              },
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('v8-evening-settlement-line')),
          findsOneWidget);
      expect(find.text('Return Qty'), findsOneWidget);
      expect(find.text('Wholesale Qty'), findsOneWidget);
      expect(find.text('Wholesale Rate ₹'), findsOneWidget);
      // Issued and initially calculated Retail Sold both start at 12 PCS.
      expect(find.text('12 PCS'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), '3');
      await tester.enterText(fields.at(1), '2');
      await tester.pumpAndSettle();
      expect(returned.text, '3');
      expect(wholesale.text, '2');
      expect(find.text('7 PCS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(fields.at(0), '12');
      await tester.pumpAndSettle();
      expect(find.textContaining('issued quantity se zyada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Retail-only closing shows Return Qty, not wholesale price',
      (tester) async {
    final returned = TextEditingController();
    final wholesale = TextEditingController();
    final rate = TextEditingController();
    addTearDown(returned.dispose);
    addTearDown(wholesale.dispose);
    addTearDown(rate.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: V8EveningClosingLine(
        productName: 'Herbal Powder',
        issuedLabel: '8',
        soldLabel: '8',
        retailRateLabel: '60.00',
        wholesaleEnabled: false,
        wholesaleQuantity: 0,
        overIssued: false,
        returnController: returned,
        wholesaleController: wholesale,
        wholesaleRateController: rate,
        onQuantityChanged: () {},
      ),
    )));
    expect(find.text('Return Qty'), findsOneWidget);
    expect(find.text('Wholesale Qty'), findsNothing);
    expect(find.text('Wholesale Rate ₹'), findsNothing);
    expect(find.textContaining('60.00'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('V8 wholesale closing continues using the canonical calculations and REST writers', () {
    final form = File('lib/screens/my_work/my_work_daily_closing.dart')
        .readAsStringSync();
    final parent = File('lib/screens/my_work/my_work_screen.dart')
        .readAsStringSync();
    final line = File('lib/widgets/v8_evening_closing_line.dart')
        .readAsStringSync();
    expect(form, contains('V8EveningClosingLine('));
    expect(form, contains('DailyOrderMath.retailSold('));
    expect(form, contains("WholePcs.parseOrZero(returns[key]!.text)"));
    expect(form, contains("WholePcs.parseOrZero(wholesale[key]!.text)"));
    expect(form, contains('ret + wh > issued + 0.0001'));
    expect(form, contains('whRate > retailRate + .005'));
    expect(form, contains('ApiPaths.eveningSave(id)'));
    expect(form, contains('ApiPaths.eveningSubmit(id)'));
    expect(form, contains('confirmEveningClosingSubmission('));
    expect(form, contains("submitError = 'Evening draft saved."));
    expect(form, contains('Unsaved Evening Closing'));
    expect(form, isNot(contains('width: 570')));
    expect(parent, contains("part 'my_work_daily_closing.dart'"));
    expect(parent, contains('v8_evening_closing_line.dart'));
    expect(line, contains('WholePcs.positiveFormatter'));
    expect(line, contains('if (overIssued)'));
  });
}
