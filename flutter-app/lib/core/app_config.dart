class AppConfig {
  static const productionApiBaseUrl =
      'https://office.excelherbal.in/wp-json/excel-herbal-erp/v7';

  /// Production is the default for the recovered app. A staging/UAT endpoint can
  /// still be supplied at build time with --dart-define=EH7_API_BASE_URL=...
  static const apiBaseUrl = String.fromEnvironment(
    'EH7_API_BASE_URL',
    defaultValue: productionApiBaseUrl,
  );

  static const environment = String.fromEnvironment(
    'EH7_ENVIRONMENT',
    defaultValue: 'production',
  );

  static bool get isProductionApi => apiBaseUrl == productionApiBaseUrl;
  static bool get isUat => environment.toLowerCase() != 'production';
}
