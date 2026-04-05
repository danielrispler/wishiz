import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/config/api_config.dart';

void main() {
  test('api base url defaults to the public wishiz host', () {
    expect(ApiConfig.baseUrl, 'https://wishiz.app');
  });

  test('share links still default to the public wishiz host', () {
    expect(ApiConfig.shareBaseUrl, 'https://wishiz.app');
  });
}
