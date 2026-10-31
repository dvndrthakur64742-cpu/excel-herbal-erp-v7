import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/widgets/evening_submit_confirmation.dart';

void main() {
  testWidgets('Review Quantities cancels Evening Submit without mutation', (
    tester,
  ) async {
    var requestedSubmissions = 0;
    bool? decision;

    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                final confirmed =
                    await confirmEveningClosingSubmission(context);
                decision = confirmed;
                if (confirmed) requestedSubmissions++;
              },
              child: const Text('Open Evening Confirmation'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Evening Confirmation'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Evening Submission'), findsOneWidget);
    expect(find.textContaining('remaining PCS'), findsOneWidget);
    expect(find.textContaining('separate authorised reviewer'), findsOneWidget);
    expect(find.text('Review Quantities'), findsOneWidget);
    expect(find.text('Confirm & Submit'), findsOneWidget);

    await tester.tap(find.text('Review Quantities'));
    await tester.pumpAndSettle();
    expect(decision, isFalse);
    expect(requestedSubmissions, 0);
    expect(find.text('Confirm Evening Submission'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Only explicit Confirm & Submit authorises submitting', (
    tester,
  ) async {
    var requestedSubmissions = 0;
    bool? decision;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                final confirmed =
                    await confirmEveningClosingSubmission(context);
                decision = confirmed;
                if (confirmed) requestedSubmissions++;
              },
              child: const Text('Open Evening Confirmation'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Evening Confirmation'));
    await tester.pumpAndSettle();

    expect(requestedSubmissions, 0);
    expect(decision, isNull);
    await tester.tap(find.text('Confirm & Submit'));
    await tester.pumpAndSettle();

    expect(decision, isTrue);
    expect(requestedSubmissions, 1);
    expect(find.text('Confirm Evening Submission'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
