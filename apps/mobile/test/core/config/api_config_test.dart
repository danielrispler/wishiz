import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/config/api_config.dart';

void main() {
  test('api mode is disabled by default without a dart define', () {
    expect(ApiConfig.baseUrl, isNull);
  });

  test('share links still default to the public wishiz host', () {
    expect(ApiConfig.shareBaseUrl, 'https://wishiz.app');
  });
}
