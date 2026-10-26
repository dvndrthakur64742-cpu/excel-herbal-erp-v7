import 'dart:io';

import 'package:excel_herbal_erp/widgets/v8_reported_tender_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('review cannot confirm implicit all-cash tender or missing evidence acknowledgement', () {
    bool allowed(String cash, String upi, bool valid, bool ack) =>
        V8ReportedTenderGuard.canConfirm(
          cashText: cash, upiText: upi,
          amountsValid: valid, acknowledged: ack,
        );
    expect(allowed('', '', true, true), isFalse);
    expect(allowed('360.00', '', true, true), isFalse);
    expect(allowed('', '360.00', true, true), isFalse);
    expect(allowed('200.00', '160.00', true, false), isFalse);
    expect(allowed('200.00', '160.00', false, true), isFalse);
    expect(allowed('0', '360.00', true, true), isTrue);
    expect(allowed('360.00', '0', true, true), isTrue);
    expect(allowed('0', '0', true, true), isTrue);
  });

  for (final width in [320.0, 390.0, 768.0, 1366.0]) {
    testWidgets('financial evidence disclosure remains accessible at ${width}px',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var acknowledged = false;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.25),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(builder: (context, update) =>
              V8ReportedTenderDisclosure(
                acknowledged: acknowledged,
                onChanged: (checked) =>
                    update(() => acknowledged = checked),
              ),
            ),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('v8-reported-tender-disclosure')),
          findsOneWidget);
      expect(find.textContaining('does NOT verify'), findsOneWidget);
      expect(find.textContaining('bank evidence are still required'),
          findsOneWidget);
      expect(acknowledged, isFalse);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(acknowledged, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(acknowledged, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  test('original finance Final Post API remains the only posting writer', () {
    final form = File('lib/screens/my_work/my_work_daily_closing.dart')
        .readAsStringSync();
    final imports = File('lib/screens/my_work/my_work_screen.dart')
        .readAsStringSync();
    expect(imports, contains('v8_reported_tender_disclosure.dart'));
    expect(form, contains('V8ReportedTenderDisclosure('));
    expect(form, contains('V8ReportedTenderGuard.canConfirm('));
    expect(form, contains('final cash = TextEditingController();'));
    expect(form, contains('final upi = TextEditingController();'));
    expect(form, contains('parsedCash != null && parsedUpi != null'));
    expect(form, contains('Cash handover and bank verification are not inferred.'));
    expect(form, isNot(contains("'Expected Deposit'")));
    expect(form, isNot(contains("'Cash Deposit'")));
    expect(form, isNot(contains('TextEditingController(text: expected.toStringAsFixed(2))')));
    expect(form, contains('DailyOrderMath.finalPostAllowed('));
    expect(form, contains('ApiPaths.finalPost(id)'));
    expect(form, contains("data: {'cash': c, 'upi': u}"));
    expect(form, contains('cash.dispose()'));
    expect(form, contains('upi.dispose()'));
  });
}
