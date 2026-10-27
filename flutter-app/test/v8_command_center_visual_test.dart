import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:excel_herbal_erp/theme/excel_brand.dart';
import 'package:excel_herbal_erp/widgets/v8_home_hero.dart';
import 'package:excel_herbal_erp/shell/v8_workspace_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppState fixture() => AppState(
  loading: false,
  authenticated: true,
  currentBranchId: 1,
  bootstrap: {
    'me': {
      'employee': {'full_name': 'Test Executive', 'designation_code': 'FSE'},
      'branch_ids': [1],
      'capabilities': <String>[],
    },
    'branches': [{'id': 1, 'name': 'Palampur'}],
  },
);

void main() {
  test('new design is distinct from old green V7 interface', () {
    expect(ExcelBrand.primary, const Color(0xFF594BE6));
    expect(ExcelBrand.sidebar, const Color(0xFFFFFFFF));
    expect(ExcelBrand.canvas, const Color(0xFFF7F8FC));
    expect(ExcelBrand.primary, isNot(const Color(0xFF0B8F48)));
  });

  for (final width in [320.0, 390.0, 768.0, 1366.0]) {
    testWidgets('clean home hero at $width does not overflow', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: ExcelBrand.lightTheme(),
        home: Scaffold(body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: V8HomeHero(app: fixture()),
          ),
        )),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('v8-home-hero')), findsOneWidget);
      expect(find.textContaining('Good '), findsOneWidget);
      if (width >= 768) {
        expect(find.byKey(const ValueKey('v8-home-artwork')), findsOneWidget);
      } else {
        expect(find.byKey(const ValueKey('v8-home-artwork')), findsNothing);
      }
    });
  }

  testWidgets('context bar keeps wired new action callback', (tester) async {
    var actions = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ExcelBrand.lightTheme(),
      home: Scaffold(body: V8WorkspaceContextBar(
        branch: 'Palampur', activeRoute: 'Overview',
        onOpenActions: () => actions++,
      )),
    ));
    expect(find.text('Excel Herbal Command Center'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('v8-create-action')));
    expect(actions, 1);
    expect(tester.takeException(), isNull);
  });
}
