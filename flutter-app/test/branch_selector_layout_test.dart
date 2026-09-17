import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('branch selector stays full width on mobile and compact on wider layouts', () {
    final source = File('lib/widgets/branch_selector.dart').readAsStringSync();

    expect(source, contains('static const double _compactBreakpoint = 600'));
    expect(source, contains('static const double _maxFieldWidth = 420'));
    expect(source, contains('constraints.maxWidth < _compactBreakpoint'));
    expect(source, contains('Alignment.centerLeft'));
    expect(source, contains('BoxConstraints(maxWidth: _maxFieldWidth)'));
  });
}
