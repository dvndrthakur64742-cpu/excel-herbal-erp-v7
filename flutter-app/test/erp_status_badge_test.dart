import 'package:excel_herbal_erp/widgets/erp_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Evening Draft, Final Post Pending and Completed have distinct tones', () {
    final draft = ErpStatusBadge.toneFor('evening_draft');
    final pending = ErpStatusBadge.toneFor('evening_submitted');
    final done = ErpStatusBadge.toneFor('completed');
    expect(draft.background, isNot(pending.background));
    expect(pending.background, isNot(done.background));
    expect(done.background, isNot(draft.background));
    expect(draft.icon, isNot(pending.icon));
    expect(pending.icon, isNot(done.icon));
  });

  test('badges distinguish rejected and unknown status without success colours',
      () {
    expect(ErpStatusBadge.toneFor('cancelled').background,
        isNot(ErpStatusBadge.toneFor('completed').background));
    expect(ErpStatusBadge.toneFor('unexpected').foreground,
        isNot(ErpStatusBadge.toneFor('completed').foreground));
  });

  testWidgets('status badge is readable, accessible and not colour-only',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(
        child: ErpStatusBadge(status: 'evening_submitted'),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Final Post Pending'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Status: Final Post Pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily workflow can retain its precise Issued wording',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ErpStatusBadge(
        status: 'issued',
        label: 'Evening Pending',
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Evening Pending'), findsOneWidget);
    expect(find.bySemanticsLabel('Status: Evening Pending'), findsOneWidget);
  });

  testWidgets('badge survives small devices with large text scale',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: const Scaffold(body: Center(
          child: ErpStatusBadge(status: 'evening_submitted'),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Final Post Pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
