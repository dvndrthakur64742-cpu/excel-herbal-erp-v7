import 'dart:async';
import 'package:excel_herbal_erp/widgets/home_query.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget page(Object scope, Future<String> Function() loader) => MaterialApp(
    home: Scaffold(body: HomeQuery<String>(scope: scope, loader: loader,
      builder: (context, snapshot, retry) {
        if (snapshot.connectionState != ConnectionState.done) return const Text('Loading');
        if (snapshot.hasError) return TextButton(onPressed: retry, child: const Text('Retry'));
        return Text(snapshot.data ?? 'Empty');
      },
    )),
  );

  testWidgets('incidental rebuild does not restart dashboard request', (tester) async {
    var calls = 0;
    Future<String> load() async { calls++; return 'Ready'; }
    await tester.pumpWidget(page('branch1', load));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page('branch1', load));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('branch switch never displays previous scope or late response', (tester) async {
    final first = Completer<String>();
    final second = Completer<String>();
    await tester.pumpWidget(page('branch1', () => first.future));
    await tester.pumpWidget(page('branch2', () => second.future));
    first.complete('Old branch');
    await tester.pump();
    expect(find.text('Old branch'), findsNothing);
    expect(find.text('Loading'), findsOneWidget);
    second.complete('New branch');
    await tester.pumpAndSettle();
    expect(find.text('New branch'), findsOneWidget);
  });

  testWidgets('retry performs a new request after failure', (tester) async {
    var calls = 0;
    Future<String> load() async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return 'Recovered';
    }
    await tester.pumpWidget(page('branch1', load));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Recovered'), findsOneWidget);
  });
}
