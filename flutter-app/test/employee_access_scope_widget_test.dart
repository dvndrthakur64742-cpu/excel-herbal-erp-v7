import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/core/providers.dart';
import 'package:excel_herbal_erp/core/secure_session.dart';
import 'package:excel_herbal_erp/screens/administration/administration_screen.dart';
import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends SecureSession {
  _Session() : super(const FlutterSecureStorage());
  @override
  Future<String?> accessToken() async => 'synthetic-access';
}

class _AccessApi extends ApiClient {
  _AccessApi(super.session);
  final writes = <Map<String, dynamic>>[];
  final roles = <Map<String, dynamic>>[
    {'id': 1, 'name': 'Stock reviewer', 'code': 'STOCK', 'capabilities': ['inventory.view']},
    {'id': 2, 'name': 'Finance reviewer', 'code': 'FIN', 'capabilities': ['finance.view']},
  ];
  List<int> assigned = [1];

  @override
  Future<dynamic> get(String path, {
    Map<String, dynamic>? query, bool authenticated = true,
  }) async {
    if (path == ApiPaths.bootstrap) {
      return {
        'me': {
          'branch_ids': [7, 8], 'assigned_branch_id': 7,
          'capabilities': ['erp.access', 'administration.access.manage'],
          'employee': {'full_name': 'Synthetic operator', 'designation_code': 'STAFF'},
        },
        'branches': [{'id': 7, 'name': 'Branch A'}, {'id': 8, 'name': 'Branch B'}],
        'navigation': {'sections': [{'id': 'home', 'label': 'Home'}],
          'bottom_nav': [{'id': 'home', 'label': 'Home'}]},
        'business_date': '2026-11-28', 'business_timezone': 'Asia/Kolkata',
        'server_timestamp': '2026-11-28T06:00:00+00:00',
        'api_contract': 'synthetic-contract', 'features': {'api_contract': 'synthetic-contract'},
      };
    }
    if (path == ApiPaths.accessMatrix) {
      return {'roles': roles, 'capabilities': ['inventory.view', 'finance.view']};
    }
    if (path == ApiPaths.accessEmployees) {
      return [{'id': 11, 'full_name': 'Target Employee', 'employee_code': 'E11',
        'designation_code': 'STAFF'}];
    }
    if (path == ApiPaths.employeeAccess(11)) {
      return {'roles': roles.where((r) => assigned.contains(r['id'])).toList(),
        'designation_defaults': <String>[], 'effective_capabilities': <String>[],
        'overrides': <Map<String, dynamic>>[]};
    }
    if (path == ApiPaths.diagnostics) return {'status': 'ok'};
    throw StateError('Unexpected synthetic GET: $path');
  }

  @override
  Future<dynamic> post(String path, {
    Map<String, dynamic>? data, bool idempotent = true, bool authenticated = true,
  }) async {
    expect(path, ApiPaths.employeeAccess(11));
    writes.add(Map<String, dynamic>.from(data!));
    assigned = List<int>.from(data['role_ids'] as List);
    return {};
  }
}

Finder field(String label) => find.byWidgetPredicate((w) =>
    w is TextField && w.decoration?.labelText == label);

void main() {
  Future<ProviderContainer> openReview(WidgetTester tester, _AccessApi api,
      _Session session) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      appStateProvider.overrideWith((ref) => AppController(api, session)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AdministrationScreen(initialSection: 'Access')),
    ));
    await tester.pumpAndSettle();
    expect(container.read(appStateProvider).bootstrapReady, isTrue);
    expect(container.read(appStateProvider).currentBranchId, 7);
    await tester.ensureVisible(find.text('Target Employee'));
    await tester.tap(find.text('Target Employee'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Find role'), 'Finance');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Stock reviewer'), findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Finance reviewer'));
    await tester.pumpAndSettle();
    expect(find.text('2 roles selected'), findsOneWidget);
    await tester.enterText(field('Change Reason'), 'Synthetic reviewed assignment');
    await tester.tap(find.text('Save Access'));
    await tester.pumpAndSettle();
    expect(find.text('Review access changes'), findsOneWidget);
    expect(api.writes, isEmpty);
    return container;
  }

  testWidgets('filtered roles retain hidden selection through reviewed save', (tester) async {
    final session = _Session();
    final api = _AccessApi(session);
    await openReview(tester, api, session);
    await tester.tap(find.text('Confirm access changes'));
    await tester.pumpAndSettle();
    expect(api.writes, hasLength(1));
    expect(api.writes.single['role_ids'], [1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branch switch during review rejects stale mutation', (tester) async {
    final session = _Session();
    final api = _AccessApi(session);
    final container = await openReview(tester, api, session);
    container.read(appStateProvider.notifier).selectBranch(8);
    await tester.pumpAndSettle();
    expect(container.read(appStateProvider).currentBranchId, 8);
    await tester.tap(find.text('Confirm access changes'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(find.textContaining('ERP scope changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
