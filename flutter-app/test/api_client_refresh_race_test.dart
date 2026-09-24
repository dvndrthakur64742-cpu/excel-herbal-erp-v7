import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bearer auth includes proxy-safe alternate header', () {
    final headers = ApiClient.bearerHeaders('token-123');
    expect(headers['Authorization'], 'Bearer token-123');
    expect(headers['X-EH7-Authorization'], 'Bearer token-123');
  });

  group('refresh token race detection', () {
    test('adopts a peer rotation when the stored refresh token changed', () {
      expect(
        ApiClient.refreshTokenWasRotated(
          'refresh-old',
          'refresh-new',
        ),
        isTrue,
      );
    });

    test('does not treat the same refresh token as a peer rotation', () {
      expect(
        ApiClient.refreshTokenWasRotated(
          'refresh-same',
          'refresh-same',
        ),
        isFalse,
      );
    });

    test('does not treat missing local refresh state as a peer rotation', () {
      expect(
        ApiClient.refreshTokenWasRotated(
          'refresh-old',
          null,
        ),
        isFalse,
      );
      expect(
        ApiClient.refreshTokenWasRotated(
          'refresh-old',
          '   ',
        ),
        isFalse,
      );
    });
  });
}
