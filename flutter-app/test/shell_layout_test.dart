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
  });
}
