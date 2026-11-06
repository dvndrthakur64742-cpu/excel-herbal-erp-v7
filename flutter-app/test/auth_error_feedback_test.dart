import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/core/secure_session.dart';
import 'package:excel_herbal_erp/core/ui_error.dart';
import 'package:excel_herbal_erp/screens/auth/login_screen.dart';
import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession extends SecureSession {
  _FakeSession() : super(const FlutterSecureStorage());
  String? token;
  int clearCount = 0;

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<void> clear() async {
    clearCount++;
    token = null;
  }
}

class _FakeApi extends ApiClient {
  _FakeApi(super.session);

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    expect(path, ApiPaths.bootstrap);
    throw const ApiException('not_authenticated', 'Expired.', 401);
  }

  @override
  Future<dynamic> login(String mobile, String password) async {
    throw const ApiException(
      'invalid_credentials',
      'Invalid login credentials.',
      401,
    );
  }
}

void main() {
  test('authenticated Flutter calls include a proxy-safe ERP bearer header', () {
    const token = 'synthetic-bearer-do-not-use';
    final headers = ApiClient.bearerHeaders(token);
    expect(headers['Authorization'], 'Bearer $token');
    expect(headers['X-EH7-Authorization'], 'Bearer $token');
    expect(headers.length, 2);
  });

  test('unauthorised login and expired session have distinct safe messages', () {
    expect(
      UiError.message(const ApiException(
        'invalid_credentials',
        'Invalid login credentials.',
        401,
      )),
      'Mobile number or password is incorrect.',
    );
    expect(
      UiError.message(const ApiException(
        'not_authenticated',
        'ERP session invalid or expired.',
        401,
      )),
      'Your session has expired. Please sign in again.',
    );
  });

  test('expired saved session at startup is silently cleared', () async {
    final session = _FakeSession()..token = 'synthetic-expired-token';
    final controller = AppController(_FakeApi(session), session);
    addTearDown(controller.dispose);

    // This verifies the constructor's unawaited cold-start bootstrap in a
    // real async unit test instead of racing the widget-test fake async clock.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(session.clearCount, 1);
    expect(session.token, isNull);
    expect(controller.state.loading, isFalse);
    expect(controller.state.authenticated, isFalse);
    expect(controller.state.error, isNull);
  });

  test('fresh sign-in 401 is not misreported as an expired session', () {
    expect(
      UiError.loginMessage(const ApiException(
        'not_authenticated',
        'Server rejected unauthenticated request.',
        401,
      )),
      'Sign-in could not be completed. Please retry or contact your administrator.',
    );
    expect(
      UiError.loginMessage(const ApiException(
        'invalid_credentials',
        'Invalid login credentials.',
        401,
      )),
      'Mobile number or password is incorrect.',
    );
    expect(
      UiError.message(const ApiException(
        'not_authenticated',
        'ERP session invalid or expired.',
        401,
      )),
      'Your session has expired. Please sign in again.',
    );
  });

  testWidgets('expired session warning goes away on typing',
      (tester) async {
    final session = _FakeSession();
    final controller = AppController(_FakeApi(session), session);
    await tester.pumpWidget(ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: LoginScreen()),
    ));
    await tester.pumpAndSettle();

    // Trigger the same 401 flow deterministically instead of racing startup.
    session.token = 'old-expired-token';
    await controller.refreshBootstrap();
    await tester.pump();
    expect(session.clearCount, 1);
    expect(session.token, isNull);
    expect(
      find.text('Your session has expired. Please sign in again.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, '9');
    await tester.pump();
    expect(
      find.text('Your session has expired. Please sign in again.'),
      findsNothing,
    );
    expect(controller.state.authenticated, isFalse);
  });

  testWidgets('rejected login explains credentials, not an expired session',
      (tester) async {
    final session = _FakeSession();
    final controller = AppController(_FakeApi(session), session);
    await tester.pumpWidget(ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: LoginScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '0000000000');
    await tester.enterText(find.byType(TextField).last, 'synthetic-wrong');
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();

    expect(find.text('Mobile number or password is incorrect.'), findsOneWidget);
    expect(find.text('Your session has expired. Please sign in again.'),
        findsNothing);
    expect(session.clearCount, 0);

    await tester.enterText(find.byType(TextField).last, 'retry-text');
    await tester.pump();
    expect(find.text('Mobile number or password is incorrect.'), findsNothing);
  });
}
