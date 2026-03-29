class ApiConfig {
  static const String baseUrlDefineKey = 'WISHIZ_API_BASE_URL';

  static String? get baseUrl {
    const configuredValue = String.fromEnvironment(baseUrlDefineKey);
    final trimmedValue = configuredValue.trim();
    if (trimmedValue.isEmpty) {
      return null;
    }

    return trimmedValue;
  }
}
