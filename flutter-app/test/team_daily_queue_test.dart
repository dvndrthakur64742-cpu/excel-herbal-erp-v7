import 'package:excel_herbal_erp/widgets/team_daily_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('defaults to open server queue and pages beyond first results', (tester) async {
    final calls = <(String,int)>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TeamDailyQueue(
      businessDate: '2026-11-26',
      load: (status,page) async {
        calls.add((status,page));
        return {'items': <Map<String,dynamic>>[], 'total': 126, 'page': page,
          'page_size': 25, 'has_more': page < 6};
      },
      onOpen: (_) {},
    ))));
    await tester.pumpAndSettle();
    expect(calls, [('open',1)]);
    expect(find.text('126 matching orders · page 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Next order page'));
    await tester.pumpAndSettle();
    expect(calls.last, ('open',2));
    expect(find.text('126 matching orders · page 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
