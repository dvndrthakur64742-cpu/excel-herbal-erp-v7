import 'package:excel_herbal_erp/widgets/async_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retry makes a new request after a failure', (tester) async {
    var attempts = 0;
    Future<dynamic> load() async {
      attempts++;
      if (attempts == 1) throw StateError('temporary failure');
      return <String>['Recovered'];
    }

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AsyncPanel(
          loader: load,
          builder: (_, data) => Text((data as List).single.toString()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Unable to load this section'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Recovered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent rebuild does not duplicate requests; reload token does', (
    tester,
  ) async {
    var attempts = 0;
    Future<dynamic> load() async => <int>[++attempts];
    Widget view(int token) => MaterialApp(
      home: Scaffold(
        body: AsyncPanel(
          loader: load,
          reloadToken: token,
          builder: (_, data) => Text('Request ${(data as List).single}'),
        ),
      ),
    );
    await tester.pumpWidget(view(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(view(1));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    await tester.pumpWidget(view(2));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Request 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
