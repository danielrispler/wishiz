class ApiConfig {
  static const String baseUrlDefineKey = 'WISHIZ_API_BASE_URL';
  static const String defaultBaseUrl = 'http://34.78.227.223:8080';

  static String? get baseUrl {
    const configuredValue = String.fromEnvironment(baseUrlDefineKey);
    final trimmedValue = configuredValue.trim();
    if (trimmedValue.isEmpty) {
      return defaultBaseUrl;
    }

    return trimmedValue;
  }
}
