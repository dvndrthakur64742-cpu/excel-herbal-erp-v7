import 'api_client.dart';

/// GET /bootstrap is read-only. Retry exactly once for transient transport or
/// gateway failure, never for expired credentials, denied authority, invalid
/// contract metadata, or a server-side application bug (HTTP 500).
abstract final class BootstrapRetryPolicy {
  static bool shouldRetry(Object error) {
    if (error is! ApiException) return false;
    final status = error.statusCode;
    if (status == 502 || status == 503 || status == 504) return true;
    return status == null && error.code == 'network_error';
  }
}
