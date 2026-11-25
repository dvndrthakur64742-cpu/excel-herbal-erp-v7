import 'dart:async';

import 'package:excel_herbal_erp/core/report_query_identity.dart';
import 'package:excel_herbal_erp/widgets/async_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report identity changes with actual date, branch, category or endpoint', () {
    final original = <String, dynamic>{
      'branch_id': 1,
      'to': '2026-11-24',
      'reporting_category': 'FIELD_EXECUTIVE',
    };
    final baseline = reportQueryIdentity('/reports/trial', original);
    for (final changed in [
      {...original, 'to': '2026-11-25'},
      {...original, 'branch_id': 2},
      {...original, 'reporting_category': 'BRANCH_MANAGER'},
      {...original, 'from': '2026-11-01'},
      {...original, 'account_id': 4},
    ]) {
      expect(reportQueryIdentity('/reports/trial', changed), isNot(baseline));
    }
    expect(reportQueryIdentity('/reports/balance-sheet', original), isNot(baseline));
    expect(reportQueryIdentity('/reports/trial', {
      'reporting_category': 'FIELD_EXECUTIVE',
      'to': '2026-11-24',
      'branch_id': 1,
    }), baseline);
  });

  testWidgets('new report date hides old rows until the new scoped result loads',
      (tester) async {
    final oldResponse = Completer<dynamic>();
    final newResponse = Completer<dynamic>();
    var requests = 0;

    Widget report(String date, Completer<dynamic> response) {
      final query = <String, dynamic>{'branch_id': 1, 'to': date};
      return MaterialApp(
        home: Scaffold(
          body: AsyncPanel(
            key: ValueKey(reportQueryIdentity('/reports/trial', query)),
            loader: () {
              requests++;
              return response.future;
            },
            builder: (context, data) => Text('Export: $data'),
          ),
        ),
      );
    }

    await tester.pumpWidget(report('2026-11-24', oldResponse));
    oldResponse.complete('old rows');
    await tester.pumpAndSettle();
    expect(find.text('Export: old rows'), findsOneWidget);
    expect(requests, 1);

    await tester.pumpWidget(report('2026-11-25', newResponse));
    expect(find.text('Export: old rows'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(requests, 2);

    newResponse.complete('new rows');
    await tester.pumpAndSettle();
    expect(find.text('Export: new rows'), findsOneWidget);
    expect(find.text('Export: old rows'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
