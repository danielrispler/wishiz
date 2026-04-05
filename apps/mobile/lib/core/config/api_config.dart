class ApiConfig {
  static const String baseUrlDefineKey = 'WISHIZ_API_BASE_URL';
  static const String shareBaseUrlDefineKey = 'WISHIZ_SHARE_BASE_URL';
  static const String defaultBaseUrl = 'https://wishiz.app';
  static const String defaultShareBaseUrl = 'https://wishiz.app';

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
