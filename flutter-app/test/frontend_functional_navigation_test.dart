import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quick actions route to their intended connected workflows', () {
    final source = File('lib/screens/home/actions_screen.dart').readAsStringSync();

    expect(source, contains("openConnectedAction('daily_create')"));
    expect(source, contains("openConnectedAction('evening')"));
    expect(source, contains("openConnectedAction('field_visit')"));
    expect(source, contains("openConnectedAction('attendance')"));
  });

  test('desktop approvals and global search keep independent tab state', () {
    final source = File('lib/shell/app_shell.dart').readAsStringSync();

    expect(source, contains("ValueKey('desktop-enterprise-approvals')"));
    expect(source, contains("ValueKey('desktop-enterprise-global-search')"));
    expect(source, contains('openConnectedAction: _openConnectedAction'));
  });
}
