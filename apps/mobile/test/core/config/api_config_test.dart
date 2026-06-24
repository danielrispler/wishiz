import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/config/api_config.dart';

void main() {
  test('api base url defaults to the public wishiz host', () {
    expect(ApiConfig.baseUrl, 'https://wishiz-api-pdst26qeja-ey.a.run.app');
  });

  test('share links still default to the public wishiz host', () {
    expect(ApiConfig.shareBaseUrl, 'https://wishiz-api-pdst26qeja-ey.a.run.app');
  });
}
