import 'dart:convert';
import 'dart:io';

class DiscoverApiClient {
  DiscoverApiClient({
    required Uri baseUri,
    required String authToken,
    HttpClient? httpClient,
  })  : _baseUri = _normalizeBaseUri(baseUri),
        _authToken = authToken,
        _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  final Uri _baseUri;
  final String _authToken;
  final HttpClient _httpClient;

  Future<Map<String, dynamic>> getFeed() async {
    final response = await _requestJson(
      'GET',
      '/discover/feed',
      expectedStatusCodes: const {HttpStatus.ok},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> toggleSave(String productId) async {
    final response = await _requestJson(
      'POST',
      '/discover/products/$productId/save',
      expectedStatusCodes: const {HttpStatus.ok},
    );
    return response as Map<String, dynamic>;
  }

  Future<void> grabStarterPack({
    required String packId,
    required String wishlistId,
  }) async {
    await _requestJson(
      'POST',
      '/discover/starter-packs/$packId/grab',
      body: {'wishlistId': wishlistId},
      expectedStatusCodes: const {HttpStatus.ok},
    );
  }

  Future<dynamic> _requestJson(
    String method,
    String path, {
    Object? body,
    required Set<int> expectedStatusCodes,
  }) async {
    final request = await _httpClient.openUrl(
      method,
      _baseUri.resolve(_trimmedPath(path)),
    );
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_authToken');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (!expectedStatusCodes.contains(response.statusCode)) {
      throw DiscoverApiException.fromResponse(
        statusCode: response.statusCode,
        responseBody: responseBody,
      );
    }

    if (responseBody.isEmpty) {
      return null;
    }
    return jsonDecode(responseBody);
  }

  static Uri _normalizeBaseUri(Uri baseUri) {
    final normalizedPath = baseUri.path.endsWith('/') && baseUri.path != '/'
        ? baseUri.path
        : '${baseUri.path}/';
    return baseUri.replace(path: normalizedPath);
  }

  static String _trimmedPath(String path) {
    if (path.startsWith('/')) {
      return path.substring(1);
    }
    return path;
  }
}

class DiscoverApiException implements IOException {
  const DiscoverApiException({
    required this.statusCode,
    required this.message,
  });

  factory DiscoverApiException.fromResponse({
    required int statusCode,
    required String responseBody,
  }) {
    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>;
      return DiscoverApiException(
        statusCode: statusCode,
        message: error['message'] as String? ?? 'Discover request failed.',
      );
    } catch (_) {
      return DiscoverApiException(
        statusCode: statusCode,
        message: 'Discover request failed.',
      );
    }
  }

  final int statusCode;
  final String message;

  @override
  String toString() =>
      'DiscoverApiException(statusCode: $statusCode, message: $message)';
}
