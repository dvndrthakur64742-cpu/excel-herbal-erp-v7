import 'package:excel_herbal_erp/core/app_version_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('app version policy', () {
    test('v7 force_update blocks outdated client', () {
      expect(
        isAppUpdateRequired(const {'force_update': true}),
        isTrue,
      );
    });

    test('force_update false does not block client even with message', () {
      expect(
        isAppUpdateRequired(const {
          'force_update': false,
          'message': 'App update required.',
        }),
        isFalse,
      );
    });

    test('legacy update_required remains a compatibility fallback', () {
      expect(
        isAppUpdateRequired(const {'update_required': true}),
        isTrue,
      );
    });

    test('missing policy fails open', () {
      expect(isAppUpdateRequired(null), isFalse);
      expect(isAppUpdateRequired(const {}), isFalse);
    });
  });
}
