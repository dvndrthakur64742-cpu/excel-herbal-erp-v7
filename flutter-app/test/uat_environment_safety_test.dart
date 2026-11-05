import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/app_config.dart';

void main() {
  test('build target is HTTPS and matches environment', () {
    expect(AppConfig.apiBaseUrl, startsWith('https://'));
    expect(AppConfig.unsafeApiTarget, isFalse);
    if (AppConfig.isUat) {
      expect(AppConfig.isProductionApi, isFalse,
          reason: 'A UAT build must never send transactions to production.');
    } else {
      expect(AppConfig.isProductionApi, isTrue,
          reason: 'A production build must explicitly target production.');
    }
  });

  test('safe default environment is isolated UAT', () {
    // In CI this is compiled with EH7_ENVIRONMENT=uat.
    if (AppConfig.isUat) {
      expect(AppConfig.apiBaseUrl, AppConfig.uatApiBaseUrl);
    }
  });
}
