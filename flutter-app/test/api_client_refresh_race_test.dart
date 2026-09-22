import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
