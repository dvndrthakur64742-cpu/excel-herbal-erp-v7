class AppConfig {
  static const productionApiBaseUrl =
      'https://office.excelherbal.in/wp-json/excel-herbal-erp/v7';

  /// The project is still in build/UAT. The API endpoint remains configurable
  /// at build time with --dart-define=EH7_API_BASE_URL=...
  static const apiBaseUrl = String.fromEnvironment(
    'EH7_API_BASE_URL',
    defaultValue: productionApiBaseUrl,
  );

  static const environment = String.fromEnvironment(
    'EH7_ENVIRONMENT',
    defaultValue: 'uat',
  );

  static bool get isProductionApi => apiBaseUrl == productionApiBaseUrl;

  /// Compile-time environment flag so release builds can tree-shake UAT-only UI.
  static const bool isUat = environment != 'production';
}
