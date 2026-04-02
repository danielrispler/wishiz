import 'dart:convert';
import 'dart:io';

import 'package:wishiz/features/wishlists/data/api/wishlist_api_dto.dart';

class WishlistApiClient {
  WishlistApiClient({
    required Uri baseUri,
    HttpClient? httpClient,
  })  : _baseUri = _normalizeBaseUri(baseUri),
        _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  final Uri _baseUri;
  final HttpClient _httpClient;

  Future<List<WishlistDto>> listWishlists() async {
    final response = await _requestJson(
      'GET',
      '/wishlists',
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return (response as List<dynamic>)
        .map((entry) => WishlistDto.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<WishlistDto> getWishlist(String id) async {
    final response = await _requestJson(
      'GET',
      '/wishlists/$id',
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return WishlistDto.fromJson(response as Map<String, dynamic>);
  }

  Future<WishlistDto> createWishlist({
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
    required bool isShared,
  }) async {
    final response = await _requestJson(
      'POST',
      '/wishlists',
      body: {
        'title': title,
        'description': description,
        'year': year,
        'coverImageUrl': coverImageUrl,
        'isShared': isShared,
      },
      expectedStatusCodes: const {HttpStatus.created},
    );

    return WishlistDto.fromJson(response as Map<String, dynamic>);
  }

  Future<WishlistDto> updateWishlist({
    required String id,
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
    required bool isShared,
  }) async {
    final response = await _requestJson(
      'PATCH',
      '/wishlists/$id',
      body: {
        'title': title,
        'description': description,
        'year': year,
        'coverImageUrl': coverImageUrl,
        'isShared': isShared,
      },
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return WishlistDto.fromJson(response as Map<String, dynamic>);
  }

  Future<void> deleteWishlist(String id) {
    return _requestJson(
      'DELETE',
      '/wishlists/$id',
      expectedStatusCodes: const {HttpStatus.noContent},
    );
  }

  Future<WishlistDto> archiveWishlist(String id) async {
    final response = await _requestJson(
      'POST',
      '/wishlists/$id/archive',
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return WishlistDto.fromJson(response as Map<String, dynamic>);
  }

  Future<WishlistDto> restoreWishlist(String id) async {
    final response = await _requestJson(
      'POST',
      '/wishlists/$id/restore',
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return WishlistDto.fromJson(response as Map<String, dynamic>);
  }

  Future<WishlistItemDto> addWishlistItem({
    required String wishlistId,
    required String title,
    String? notes,
    String? priceLabel,
    required String priority,
    required String status,
    String? imageUrl,
    String? productUrl,
  }) async {
    final response = await _requestJson(
      'POST',
      '/wishlists/$wishlistId/items',
      body: {
        'title': title,
        'notes': notes,
        'priceLabel': priceLabel,
        'priority': priority,
        'status': status,
        'imageUrl': imageUrl,
        'productUrl': productUrl,
      },
      expectedStatusCodes: const {HttpStatus.created},
    );

    return WishlistItemDto.fromJson(response as Map<String, dynamic>);
  }

  Future<WishlistItemDto> updateWishlistItem({
    required String wishlistId,
    required String itemId,
    required Map<String, dynamic> body,
  }) async {
    final response = await _requestJson(
      'PATCH',
      '/wishlists/$wishlistId/items/$itemId',
      body: body,
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return WishlistItemDto.fromJson(response as Map<String, dynamic>);
  }

  Future<void> deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  }) {
    return _requestJson(
      'DELETE',
      '/wishlists/$wishlistId/items/$itemId',
      expectedStatusCodes: const {HttpStatus.noContent},
    );
  }

  Future<WishlistDto> reorderWishlistItems({
    required String wishlistId,
    required List<String> orderedItemIds,
  }) async {
    final response = await _requestJson(
      'POST',
      '/wishlists/$wishlistId/items/reorder',
      body: {
        'orderedItemIds': orderedItemIds,
      },
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return WishlistDto.fromJson(response as Map<String, dynamic>);
  }

  Future<dynamic> _requestJson(
    String method,
    String path, {
    Object? body,
    required Set<int> expectedStatusCodes,
  }) async {
    final request =
        await _httpClient.openUrl(method, _baseUri.resolve(_trimmedPath(path)));
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);

    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (!expectedStatusCodes.contains(response.statusCode)) {
      throw WishlistApiException.fromResponse(
        statusCode: response.statusCode,
        responseBody: responseBody,
      );
    }

    if (responseBody.trim().isEmpty) {
      return null;
    }

    return jsonDecode(responseBody);
  }

  static Uri _normalizeBaseUri(Uri baseUri) {
    final normalizedPath =
        baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
    return baseUri.replace(path: normalizedPath.isEmpty ? '/' : normalizedPath);
  }

  static String _trimmedPath(String path) {
    if (path.startsWith('/')) {
      return path.substring(1);
    }

    return path;
  }
}

class WishlistApiException implements IOException {
  const WishlistApiException({
    required this.message,
    this.statusCode,
    this.code,
  });

  factory WishlistApiException.fromResponse({
    required int statusCode,
    required String responseBody,
  }) {
    final fallbackMessage = 'Wishlist API request failed ($statusCode).';
    if (responseBody.trim().isEmpty) {
      return WishlistApiException(
        message: fallbackMessage,
        statusCode: statusCode,
      );
    }

    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      final message = error?['message'] as String?;
      final code = error?['code'] as String?;

      return WishlistApiException(
        message: message == null || message.isEmpty ? fallbackMessage : message,
        statusCode: statusCode,
        code: code,
      );
    } catch (_) {
      return WishlistApiException(
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
