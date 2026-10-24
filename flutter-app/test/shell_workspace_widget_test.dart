import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/secure_session.dart';
import 'package:excel_herbal_erp/shell/app_shell.dart';
import 'package:excel_herbal_erp/state/app_state.dart';

const session = SecureSession(FlutterSecureStorage());
class FixtureController extends AppController {
  FixtureController(AppState fixture) : super(ApiClient(session), session) {
    state = fixture;
  }
  @override
  Future<void> initialize() async {}
  void replace(AppState fixture) { state = fixture; }
}

AppState fixture({bool authorised = true}) => AppState(
  loading: false, authenticated: true, currentBranchId: authorised ? 1 : null,
  bootstrap: {
    'me': {
      'employee': {'full_name': 'Test Employee', 'designation_code': 'FIELD'},
      'branch_ids': authorised ? [1] : [],
      'capabilities': <String>[],
    },
    'branches': [{'id': 1, 'name': 'Test Branch'}],
    'navigation': {
      'sections': [{'id': 'home'}, {'id': 'my_work'}],
      // Deliberately stale unauthorized items and duplicate route.
      'bottom_nav': [
        {'id': 'home', 'label': 'Home'},
        {'id': 'my_work', 'label': 'My Work'},
        {'id': 'approvals', 'label': 'Approvals'},
        {'id': 'actions', 'label': 'Create'},
        {'id': 'home', 'label': 'Duplicate Home'},
        {'id': 'profile', 'label': 'Profile'},
      ],
    },
  },
);

void main() {
  for (final width in [360.0, 390.0, 768.0, 1366.0]) {
    testWidgets('actual shell layout and permission filtering at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = FixtureController(fixture());
      final capture = GlobalKey();
      await tester.pumpWidget(ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => controller)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: RepaintBoundary(key: capture, child: const AppShell()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Duplicate Home'), findsNothing);
      expect(find.text('Approvals'), findsNothing);
      expect(find.text('Create'), findsNothing);
      expect(find.text('Finance Workspace'), findsNothing);
      if (width < 1100) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        expect(find.text('Find Records'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'My Work'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/ui-evidence')..createSync(recursive: true);
        File('${dir.path}/shell-${width.toInt()}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      if (width < 1100) {
        await tester.tap(find.byTooltip('Close menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('My Work')));
        await tester.pumpAndSettle();
        expect(find.text('No authorised My Work functions.'), findsOneWidget);
      }
      controller.replace(fixture(authorised: false));
      await tester.pumpAndSettle();
      expect(find.text('Finance Workspace'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
