import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/core/bootstrap_retry_policy.dart';
import 'package:excel_herbal_erp/core/secure_session.dart';
import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestSession extends SecureSession {
  _TestSession() : super(const FlutterSecureStorage());
  String? token = 'synthetic-test-token';

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<void> clear() async {
    token = null;
  }
}

class _StubBootstrapApi extends ApiClient {
  _StubBootstrapApi(super.session, this.responses);
  final List<Object> responses;
  int calls = 0;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    expect(path, ApiPaths.bootstrap);
    final result = responses[calls++];
    if (result is Exception) throw result;
    return result;
  }
}

Map<String, dynamic> _validBootstrap() => {
      'business_date': '2026-11-04',
      'business_timezone': 'Asia/Kolkata',
      'server_timestamp': '2026-11-04T04:22:30+00:00',
      'api_contract': '7.3.12-contract-refund-evidence-1',
      'features': {'api_contract': '7.3.12-contract-refund-evidence-1'},
    };

void main() {
  test('only transient GET bootstrap failures can automatically retry', () {
    for (final status in [502, 503, 504]) {
      expect(
        BootstrapRetryPolicy.shouldRetry(
          ApiException('gateway_failure', 'Temporary outage', status),
        ),
        isTrue,
      );
    }
    expect(
      BootstrapRetryPolicy.shouldRetry(
        const ApiException('network_error', 'Offline'),
      ),
      isTrue,
    );
    for (final status in [400, 401, 403, 422, 429, 500]) {
      expect(
        BootstrapRetryPolicy.shouldRetry(
          ApiException('network_error', 'Do not retry', status),
        ),
        isFalse,
      );
    }
    expect(BootstrapRetryPolicy.shouldRetry(StateError('bad payload')), isFalse);
  });

  test('startup retries one transient GET and accepts valid server contract',
      () async {
    final session = _TestSession();
    final api = _StubBootstrapApi(session, [
      const ApiException('network_error', 'Temporary connection failure'),
      _validBootstrap(),
    ]);
    final controller = AppController(api, session);
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 460));
    expect(api.calls, 2);
    expect(controller.state.authenticated, isTrue);
    expect(controller.state.bootstrapReady, isTrue);
    expect(controller.state.businessDate, '2026-11-04');
    expect(controller.state.error, isNull);
  });

  test('permission failure is not retried and shows safe support reference',
      () async {
    final session = _TestSession();
    final api = _StubBootstrapApi(session, [
      const ApiException('branch_forbidden', 'Forbidden', 403, 'req-safe-42'),
    ]);
    final controller = AppController(api, session);
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(api.calls, 1);
    expect(controller.state.authenticated, isTrue);
    expect(controller.state.bootstrapReady, isFalse);
    expect(controller.state.errorReference, 'req-safe-42');
    expect(controller.state.bootstrapFailureMessage,
        'Your role is not authorised for this action.');
  });

  test('expired session clears credentials without retrying bootstrap',
      () async {
    final session = _TestSession();
    final api = _StubBootstrapApi(session, [
      const ApiException('not_authenticated', 'Sign in again', 401),
    ]);
    final controller = AppController(api, session);
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(api.calls, 1);
    expect(session.token, isNull);
    expect(controller.state.authenticated, isFalse);
    expect(controller.state.loading, isFalse);
  });

  test('invalid server contract never triggers another network request',
      () async {
    final session = _TestSession();
    final broken = _validBootstrap()
      ..['business_date'] = '2026-02-30';
    final api = _StubBootstrapApi(session, [broken]);
    final controller = AppController(api, session);
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(api.calls, 1);
    expect(controller.state.bootstrapReady, isFalse);
    expect(controller.state.bootstrapFailureMessage,
        'ERP server business date is unavailable or invalid.');
  });

  test('clearing startup error also removes previous support reference', () {
    const failed = AppState(
      loading: false,
      authenticated: true,
      error: 'Temporary error',
      errorReference: 'req-safe-42',
    );
    final retried = failed.copyWith(loading: true, clearError: true);
    expect(retried.error, isNull);
    expect(retried.errorReference, isNull);
  });
}
