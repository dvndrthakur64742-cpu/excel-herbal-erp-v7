import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/secure_session.dart';
import 'package:excel_herbal_erp/screens/auth/login_screen.dart';
import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoSession extends SecureSession {
  const _NoSession() : super(const FlutterSecureStorage());

  @override
  Future<String?> accessToken() async => null;
}

Widget _loginApp({double textScale = 1}) {
  const session = _NoSession();
  return ProviderScope(
    overrides: [
      appStateProvider.overrideWith(
        (ref) => AppController(ApiClient(session), session),
      ),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const LoginScreen(),
      ),
    ),
  );
}

void main() {
  testWidgets('login help explains the safe administrator assistance path',
      (tester) async {
    await tester.pumpWidget(_loginApp());
    await tester.pumpAndSettle();

    expect(find.text('Forgot password or need help?'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, hasLength(2));
    expect(fields.first.autofillHints, contains(AutofillHints.username));
    expect(fields.last.autofillHints, contains(AutofillHints.password));
    expect(fields.last.obscureText, isTrue);
    expect(fields.last.autocorrect, isFalse);
    expect(fields.last.enableSuggestions, isFalse);

    await tester.tap(find.text('Forgot password or need help?'));
    await tester.pumpAndSettle();

    expect(find.text('Need help signing in?'), findsOneWidget);
    expect(find.textContaining('contact your branch manager or Head Office'),
        findsOneWidget);
    expect(find.textContaining('Never share your password or OTP'),
        findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Need help signing in?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login stays usable with large text on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_loginApp(textScale: 2));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Forgot password or need help?'));
    await tester.tap(find.text('Forgot password or need help?'));
    await tester.pumpAndSettle();
    expect(find.text('Need help signing in?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
