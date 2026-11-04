import 'package:excel_herbal_erp/widgets/startup_recovery_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('small phone scrolls to Retry and Logout without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var retries = 0;
    var logouts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StartupRecoveryPanel(
          message: List.filled(7, 'The server is temporarily unavailable. ').join(),
          supportReference: 'req-safe-42',
          onRetry: () => retries++,
          onLogout: () => logouts++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ERP startup temporarily unavailable'), findsOneWidget);
    expect(find.text('Support reference: req-safe-42'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.ensureVisible(find.text('Retry startup'));
    await tester.tap(find.text('Retry startup'));
    await tester.pumpAndSettle();
    expect(retries, 1);

    await tester.ensureVisible(find.text('Logout'));
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(logouts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop has accessible recovery actions without reference', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StartupRecoveryPanel(
          message: 'Startup API is unavailable',
          onRetry: () => retried = true,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Support reference:'), findsNothing);
    expect(find.text('Retry startup'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    await tester.tap(find.text('Retry startup'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });
}
