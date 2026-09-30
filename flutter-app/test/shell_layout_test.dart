import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/shell/shell_layout.dart';

void main() {
  test('shell uses one desktop breakpoint across layout and routing', () {
    expect(ShellLayout.isDesktopWidth(959), isFalse);
    expect(ShellLayout.isDesktopWidth(960), isTrue);
    expect(ShellLayout.isDesktopWidth(1099), isTrue);
    expect(ShellLayout.isDesktopWidth(1100), isTrue);

    final source = File('lib/shell/app_shell.dart').readAsStringSync();
    expect(source, contains('ShellLayout.isDesktopWidth(constraints.maxWidth)'));
    expect(source, contains('ShellLayout.isDesktopWidth(MediaQuery.sizeOf(context).width)'));
    expect(source, isNot(contains('>= 1100')));
    expect(source, contains('final effectiveRoute = _routeAllowed(app, desktopRoute)'));
    expect(source, contains('final child = switch (effectiveRoute)'));
    expect(
      source,
      isNot(contains("if (!_routeAllowed(app, desktopRoute)) desktopRoute = 'home';")),
    );
  });

  test('shared shell routes stay synchronized across responsive changes', () {
    final source = File('lib/shell/app_shell.dart').readAsStringSync();

    expect(source, contains('void _selectDesktopRoute(String id)'));
    expect(source, contains('desktopRoute = id;'));
    expect(source, contains('if (index >= 0) mobileIndex = index;'));
    expect(source, contains('mobileIndex = index;'));
    expect(source, contains('desktopRoute = id;'));
  });
}
