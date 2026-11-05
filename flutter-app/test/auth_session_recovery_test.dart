import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/core/secure_session.dart';
import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySession extends SecureSession {
  _MemorySession() : super(const FlutterSecureStorage());

  String? token;
  int clearCalls = 0;

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<void> clear() async {
    clearCalls++;
    token = null;
  }
}

class _UnreadableSession extends _MemorySession {
  @override
  Future<String?> accessToken() async => throw StateError('synthetic storage read failure');
}

Map<String, dynamic> _bootstrap() => {
      'me': {
        'branch_ids': [7],
        'assigned_branch_id': 7,
        'capabilities': ['erp.access', 'sales.view'],
        'employee': {
          'full_name': 'Synthetic Employee',
          'designation_code': 'STAFF',
        },
      },
      'branches': [
        {'id': 7, 'name': 'Synthetic Branch'},
      ],
      'navigation': {
        'sections': [
          {'id': 'home', 'label': 'Home'},
          {'id': 'sales', 'label': 'Sales'},
        ],
        'bottom_nav': [
          {'id': 'home', 'label': 'Home'},
        ],
      },
      'business_date': '2026-11-05',
      'business_timezone': 'Asia/Kolkata',
      'server_timestamp': '2026-11-05T04:00:00+00:00',
      'api_contract': 'synthetic-contract',
      'features': {'api_contract': 'synthetic-contract'},
    };

class _FlowApi extends ApiClient {
  _FlowApi(this.testSession) : super(testSession);

  final _MemorySession testSession;
  int loginCalls = 0;
  int bootstrapCalls = 0;
  int logoutCalls = 0;
  int? bootstrapError;

  @override
  Future<dynamic> login(String mobile, String password) async {
    expect(mobile, '0000000000');
    expect(password, 'synthetic-only');
    loginCalls++;
    testSession.token = 'synthetic-access-token';
    return const {
      'access_token': 'synthetic-access-token',
      'refresh_token': 'synthetic-refresh-token',
    };
  }

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    expect(path, ApiPaths.bootstrap);
    bootstrapCalls++;
    if (bootstrapError == 401) {
      throw const ApiException('session_expired', 'Please sign in again', 401);
    }
    if (bootstrapError == 403) {
      throw const ApiException('branch_forbidden', 'Not authorised', 403, 'synthetic-ref');
    }
    return _bootstrap();
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    await testSession.clear();
  }
}

void main() {
  test('login -> authorised home projection -> logout clears local session',
      () async {
    final session = _MemorySession();
    final api = _FlowApi(session);
    final controller = AppController(api, session);
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(controller.state.loading, isFalse);
    expect(controller.state.authenticated, isFalse);

    await controller.login('0000000000', 'synthetic-only');
    expect(api.loginCalls, 1);
    expect(api.bootstrapCalls, 1);
    expect(controller.state.loading, isFalse);
    expect(controller.state.authenticated, isTrue);
    expect(controller.state.bootstrapReady, isTrue);
    expect(controller.state.sectionVisible('home'), isTrue);
    expect(controller.state.can('sales.view'), isTrue);
    expect(controller.state.currentBranchId, 7);

    await controller.logout();
    expect(api.logoutCalls, 1);
    expect(session.clearCalls, 1);
    expect(session.token, isNull);
    expect(controller.state.authenticated, isFalse);
    expect(controller.state.bootstrap, isNull);
  });

  test('expired bootstrap session removes local credentials and home authority',
      () async {
    final session = _MemorySession();
    final api = _FlowApi(session);
    final controller = AppController(api, session);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    await controller.login('0000000000', 'synthetic-only');
    expect(controller.state.can('sales.view'), isTrue);

    api.bootstrapError = 401;
    await controller.refreshBootstrap();
    expect(api.bootstrapCalls, 2);
    expect(session.clearCalls, 1);
    expect(session.token, isNull);
    expect(controller.state.authenticated, isFalse);
    expect(controller.state.can('sales.view'), isFalse);
  });

  test('403 revokes stale branch UI authority without resetting local session',
      () async {
    final session = _MemorySession();
    final api = _FlowApi(session);
    final controller = AppController(api, session);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    await controller.login('0000000000', 'synthetic-only');
    expect(controller.state.can('sales.view'), isTrue);

    api.bootstrapError = 403;
    await controller.refreshBootstrap();
    expect(controller.state.authenticated, isTrue);
    expect(controller.state.bootstrapReady, isFalse);
    expect(controller.state.can('sales.view'), isFalse);
    expect(controller.state.sectionVisible('sales'), isFalse);
    expect(controller.state.errorReference, 'synthetic-ref');
    expect(session.token, 'synthetic-access-token');
    expect(session.clearCalls, 0);

    api.bootstrapError = null;
    await controller.retryBootstrap();
    expect(controller.state.bootstrapReady, isTrue);
    expect(controller.state.can('sales.view'), isTrue);
  });

  test('unreadable secure storage exits loading without deleting credentials',
      () async {
    final session = _UnreadableSession();
    final api = _FlowApi(session);
    final controller = AppController(api, session);
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.state.loading, isFalse);
    expect(controller.state.authenticated, isFalse);
    expect(controller.state.error, contains('Unable to read your saved session'));
    expect(session.clearCalls, 0);
    expect(api.bootstrapCalls, 0);
  });
}
