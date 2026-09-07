class AppConfig {
  static const productionApiBaseUrl =
      'https://office.excelherbal.in/wp-json/excel-herbal-erp/v7';

  /// Safe compiler default. The office endpoint is allowed for UAT only when
  /// explicitly supplied by the build pipeline; it is never selected implicitly.
  static const apiBaseUrl = String.fromEnvironment(
    'EH7_API_BASE_URL',
    defaultValue: 'https://uat.invalid/wp-json/excel-herbal-erp/v7',
  );

  static const environment = String.fromEnvironment(
    'EH7_ENVIRONMENT',
    defaultValue: 'uat',
  );

  static bool get isProductionApi => apiBaseUrl == productionApiBaseUrl;
  static bool get isUat => environment.toLowerCase() != 'production';
}
