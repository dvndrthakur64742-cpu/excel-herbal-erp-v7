import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('command login uses new split layout and retains original secure login', () {
    final source = File('lib/screens/auth/login_screen.dart').readAsStringSync();
    expect(source, contains("constraints.maxWidth >= 920"));
    expect(source, contains("ValueKey('v8-command-login-intro')"));
    expect(source, contains("ValueKey('v8-command-login')"));
    expect(source, contains("ValueKey('v8-command-signin')"));
    expect(source, contains("labelText: 'Mobile number'"));
    expect(source, contains("labelText: 'Password'"));
    expect(source, contains("Semantics("));
    expect(source, contains('liveRegion: true'));
    expect(source, contains('ref.read(appStateProvider.notifier).login(mobileValue, password.text)'));
    expect(source, isNot(contains("Employee Workspace")));
  });
}
