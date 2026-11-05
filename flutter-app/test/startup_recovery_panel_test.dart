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

  testWidgets('all breakpoints keep usable 48px actions with enlarged text', (
    tester,
  ) async {
    var retries = 0;
    var logouts = 0;
    for (final width in <double>[320, 360, 390, 768, 1366]) {
      await tester.binding.setSurfaceSize(Size(width, 640));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(width <= 390 ? 2 : 1),
              ),
              child: StartupRecoveryPanel(
                message: 'Unable to validate the ERP server startup contract.',
                supportReference: 'req-synthetic-123',
                onRetry: () => retries++,
                onLogout: () => logouts++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ERP startup temporarily unavailable'), findsOneWidget);
      expect(find.text('Support reference: req-synthetic-123'), findsOneWidget);
      // FilledButton.icon and TextButton.icon use private widget subtypes.
      // Predicate matching includes those subtypes and preserves the 48px check.
      final retry = find.byWidgetPredicate((widget) => widget is FilledButton);
      final logout = find.byWidgetPredicate((widget) => widget is TextButton);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(logout).height, greaterThanOrEqualTo(48));
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.ensureVisible(logout);
      await tester.pumpAndSettle();
      await tester.tap(logout);
      expect(tester.takeException(), isNull);
    }
    expect(retries, 5);
    expect(logouts, 5);
    await tester.binding.setSurfaceSize(null);
  });
}
