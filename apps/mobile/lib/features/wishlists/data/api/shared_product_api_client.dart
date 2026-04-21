import 'dart:convert';
import 'dart:io';

class SharedProductApiClient {
  SharedProductApiClient({required Uri baseUri, HttpClient? httpClient})
    : _baseUri = _normalizeBaseUri(baseUri),
      _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  final Uri _baseUri;
  final HttpClient _httpClient;

  Future<ScrapedProductResponse> scrapeProduct(
    String productUrl, {
    String targetCurrencyCode = 'USD',
  }) async {
    final request = await _httpClient.getUrl(
      _baseUri
          .resolve('scrape')
          .replace(
            queryParameters: {
              'url': productUrl,
              'targetCurrencyCode': targetCurrencyCode,
            },
          ),
    );
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode != HttpStatus.ok) {
      throw SharedProductApiException.fromResponse(
        statusCode: response.statusCode,
        responseBody: responseBody,
      );
    }

    return ScrapedProductResponse.fromJson(
      jsonDecode(responseBody) as Map<String, dynamic>,
    );
  }

  static Uri _normalizeBaseUri(Uri baseUri) {
    final normalizedPath = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';
    return baseUri.replace(path: normalizedPath.isEmpty ? '/' : normalizedPath);
  }
}

class ScrapedProductResponse {
  const ScrapedProductResponse({
    required this.name,
    required this.priceAmount,
    required this.priceCurrency,
    required this.imageUrl,
    required this.source,
  });

  factory ScrapedProductResponse.fromJson(Map<String, dynamic> json) {
    return ScrapedProductResponse(
      name: json['name'] as String? ?? '',
      priceAmount: json['priceAmount'] as String? ?? '',
      priceCurrency: json['priceCurrency'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      source: json['source'] as String? ?? '',
    );
  }

  final String name;
  final String priceAmount;
  final String priceCurrency;
  final String imageUrl;
  final String source;
}

class SharedProductApiException implements IOException {
  const SharedProductApiException({
    required this.message,
    this.statusCode,
    this.code,
  });

  factory SharedProductApiException.fromResponse({
    required int statusCode,
    required String responseBody,
  }) {
    final fallbackMessage = 'Product scrape request failed ($statusCode).';
    if (responseBody.trim().isEmpty) {
      return SharedProductApiException(
        message: fallbackMessage,
        statusCode: statusCode,
      );
    }

    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      final message = error?['message'] as String?;
      final code = error?['code'] as String?;

      return SharedProductApiException(
        message: message == null || message.isEmpty ? fallbackMessage : message,
        statusCode: statusCode,
        code: code,
      );
    } catch (_) {
      return SharedProductApiException(
        message: fallbackMessage,
        statusCode: statusCode,
      );
    }
  }

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}
