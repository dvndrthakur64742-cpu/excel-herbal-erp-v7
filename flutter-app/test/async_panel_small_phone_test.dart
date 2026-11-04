import 'package:excel_herbal_erp/widgets/async_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('large-text small phone keeps error Retry reachable and functional',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var attempts = 0;
    Future<dynamic> load() async {
      attempts++;
      if (attempts == 1) throw StateError('temporary offline');
      return <String>['Recovered safely'];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
          child: Scaffold(
            body: AsyncPanel(
              loader: load,
              builder: (_, value) => Text((value as List).single.toString()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Unable to load this section'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Recovered safely'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large-text empty state stays scrollable on narrow phones',
      (tester) async {
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
          child: Scaffold(
            body: AsyncPanel(
              loader: () async => <String>[],
              emptyMessage:
                  'No assigned records for your current branch and selected business date. You can review your filters or return to your dashboard.',
              builder: (_, value) => const Text('Should not show'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('No records yet'), findsOneWidget);
    expect(find.text('Should not show'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
