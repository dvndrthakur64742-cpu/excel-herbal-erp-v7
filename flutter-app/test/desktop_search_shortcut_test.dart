import 'package:excel_herbal_erp/shell/desktop_search_shortcut.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search shortcut only works when permitted and preserves focused form', (tester) async {
    int calls = 0;
    Widget page(bool allowed) => MaterialApp(home: Scaffold(body:
      DesktopSearchShortcut(enabled: allowed, onSearch: () => calls++,
        child: const TextField(key: ValueKey('draft')))));
    await tester.pumpWidget(page(true));
    await tester.tap(find.byKey(const ValueKey('draft')));
    await tester.enterText(find.byKey(const ValueKey('draft')), 'Unsaved draft');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(calls, 1);
    expect(find.text('Unsaved draft'), findsOneWidget);
    await tester.pumpWidget(page(false));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(calls, 1);
  });
}
