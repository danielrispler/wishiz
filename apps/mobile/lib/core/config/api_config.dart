class ApiConfig {
  static const String baseUrlDefineKey = 'WISHIZ_API_BASE_URL';
  static const String shareBaseUrlDefineKey = 'WISHIZ_SHARE_BASE_URL';
  static const String defaultBaseUrl =
      'https://wishiz-api-pdst26qeja-ey.a.run.app';
  // Share/deep-link landing, assetlinks.json and apple-app-site-association are
  // all served by the API itself, so the share base is the same Cloud Run host.
  static const String defaultShareBaseUrl = defaultBaseUrl;

  static String get baseUrl {
    const configuredValue = String.fromEnvironment(baseUrlDefineKey);
    final trimmedValue = configuredValue.trim();
    if (trimmedValue.isEmpty) {
      return defaultBaseUrl;
    }

    return trimmedValue;
  }

  static String get shareBaseUrl {
    const configuredValue = String.fromEnvironment(shareBaseUrlDefineKey);
    final trimmedValue = configuredValue.trim();
    if (trimmedValue.isEmpty) {
      return defaultShareBaseUrl;
    }

    return trimmedValue;
  }
}
