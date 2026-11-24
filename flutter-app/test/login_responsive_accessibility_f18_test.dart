// F18: staff sign-in accessibility across phone, split-screen and desktop.
// Fully isolated widget tests; no API network calls or production credentials.
import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/secure_session.dart';
import 'package:excel_herbal_erp/screens/auth/login_screen.dart';
import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestSession extends SecureSession {
  const _TestSession() : super(const FlutterSecureStorage());

  @override
  Future<String?> accessToken() async => null;
}

class _NoNetworkApi extends ApiClient {
  _NoNetworkApi(super.session);
  int attempts = 0;

  @override
  Future<dynamic> login(String mobile, String password) async {
    attempts++;
    // Fake server-only rejection; never touches Office or any staging API.
    throw const ApiException('invalid_credentials',
        'Invalid login credentials.', 401);
  }
}

Widget _screen(_NoNetworkApi api, _TestSession session,
    {double textScale = 1}) {
  return ProviderScope(
    overrides: [
      appStateProvider.overrideWith(
        (ref) => AppController(api, session),
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
  testWidgets('F18 sign-in remains accessible across 6 widths with enlarged text',
      (tester) async {
    const sizes = <Size>[
      Size(240, 440), // very small split-screen
      Size(320, 568),
      Size(360, 700),
      Size(390, 844),
      Size(768, 900), // tablet
      Size(1366, 768), // desktop
    ];

    for (final size in sizes) {
      for (final scale in <double>[1.0, 2.0]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final session = _TestSession();
        final api = _NoNetworkApi(session);
        await tester.pumpWidget(_screen(api, session, textScale: scale));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNWidgets(2),
            reason: 'Username and password fields missing at $size/$scale');
        final fields = tester.widgetList<TextField>(
            find.byType(TextField)).toList();
        expect(fields.first.keyboardType, TextInputType.phone);
        expect(fields.first.autofillHints, contains(AutofillHints.username));
        expect(fields.last.autofillHints, contains(AutofillHints.password));
        expect(fields.last.obscureText, isTrue);
        expect(find.text('SIGN IN'), findsOneWidget);

        // A narrow or zoomed screen must scroll to reach the submit button.
        await tester.ensureVisible(find.text('SIGN IN'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('SIGN IN'));
        await tester.pumpAndSettle();
        expect(find.text('Enter your mobile number.'), findsOneWidget,
            reason: 'Empty login validation missing at $size/$scale');
        expect(api.attempts, 0,
            reason: 'Empty login must never call the authentication API');
        expect(tester.takeException(), isNull,
            reason: 'Login overflow/exception at $size/$scale');
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('F18 password visibility and validation guide a phone user',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const session = _TestSession();
    final api = _NoNetworkApi(session);
    await tester.pumpWidget(_screen(api, session, textScale: 2));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '9000000002');
    await tester.ensureVisible(find.text('SIGN IN'));
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(api.attempts, 0);

    await tester.enterText(find.byType(TextField).last, 'synthetic-fake-password');
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isTrue);

    await tester.ensureVisible(find.text('SIGN IN'));
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();
    expect(api.attempts, 1);
    expect(find.text('Mobile number or password is incorrect.'),
        findsOneWidget);
    expect(find.text('Your session has expired. Please sign in again.'),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('F18 accessible help dialog opens in short landscape viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const session = _TestSession();
    await tester.pumpWidget(_screen(_NoNetworkApi(session), session,
        textScale: 2));
    await tester.pumpAndSettle();
    final help = find.text('Forgot password or need help?');
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();

    expect(find.text('Need help signing in?'), findsOneWidget);
    expect(find.textContaining('contact your branch manager or Head Office'),
        findsOneWidget);
    expect(find.textContaining('Never share your password or OTP'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Need help signing in?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
