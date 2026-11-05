class AppConfig {
  static const productionApiBaseUrl =
      'https://office.excelherbal.in/wp-json/excel-herbal-erp/v7';

  // Dedicated sandbox: never use a production WordPress host for UAT.
  static const uatApiBaseUrl =
      'https://wordpress-uat-production.up.railway.app/wp-json/excel-herbal-erp/v7';

  static const environment = String.fromEnvironment(
    'EH7_ENVIRONMENT',
    defaultValue: 'uat',
  );

  // Build-time override is supported for isolated developer environments.
  // Safe defaults keep development builds away from real employee/customer data.
  static const apiBaseUrl = String.fromEnvironment(
    'EH7_API_BASE_URL',
    defaultValue: environment == 'production'
        ? productionApiBaseUrl
        : uatApiBaseUrl,
  );

  static const bool isProduction = environment == 'production';
  static const bool isUat = !isProduction;
  static bool get isProductionApi =>
      Uri.tryParse(apiBaseUrl)?.host.toLowerCase() ==
      Uri.parse(productionApiBaseUrl).host.toLowerCase();

  // Wrong environment/host combinations MUST be blocked before any API call.
  // In particular, a UAT build must not post transactions on the live domain.
  static bool get unsafeApiTarget {
    final target = Uri.tryParse(apiBaseUrl);
    if (target == null ||
        target.scheme != 'https' ||
        target.host.isEmpty ||
        target.userInfo.isNotEmpty ||
        target.hasQuery ||
        target.hasFragment) {
      return true;
    }
    if (isProduction) {
      return apiBaseUrl.replaceFirst(RegExp(r'/$'), '') !=
          productionApiBaseUrl;
    }
    return isProductionApi;
  }
}
