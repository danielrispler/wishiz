import 'dart:convert';
import 'dart:io';

import 'package:wishiz/features/product_imports/domain/product_import_job.dart';

class ProductImportApiClient {
  ProductImportApiClient({
    required Uri baseUri,
    required String authToken,
    HttpClient? httpClient,
  }) : _baseUri = _normalizeBaseUri(baseUri),
       _authToken = authToken,
       _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  final Uri _baseUri;
  final String _authToken;
  final HttpClient _httpClient;

  Future<ProductImportJob> enqueue({
    String? wishlistId,
    required String sharedText,
    required String clientRequestId,
    required String targetCurrencyCode,
  }) async {
    final body = <String, dynamic>{
      'sharedText': sharedText,
      'clientRequestId': clientRequestId,
      'targetCurrencyCode': targetCurrencyCode,
    };
    if (wishlistId != null) {
      body['wishlistId'] = wishlistId;
    }
    final response = await _requestJson(
      'POST',
      '/product-imports',
      body: body,
      expectedStatusCodes: const {HttpStatus.ok, HttpStatus.created},
    );
    return ProductImportJobDto.fromJson(
      response as Map<String, dynamic>,
    ).toEntity();
  }

  Future<ProductImportJob> assign(String id, String wishlistId) async {
    final response = await _requestJson(
      'POST',
      '/product-imports/$id/assign',
      body: {'wishlistId': wishlistId},
      expectedStatusCodes: const {HttpStatus.ok},
    );
    return ProductImportJobDto.fromJson(
      response as Map<String, dynamic>,
    ).toEntity();
  }

  Future<List<ProductImportJob>> list({int limit = 25}) async {
    final response = await _requestJson(
      'GET',
      '/product-imports?limit=$limit',
      expectedStatusCodes: const {HttpStatus.ok},
    );
    return (response as List<dynamic>)
        .map(
          (entry) => ProductImportJobDto.fromJson(
            entry as Map<String, dynamic>,
          ).toEntity(),
        )
        .toList(growable: false);
  }

  Future<ProductImportJob> retry(String id) async {
    final response = await _requestJson(
      'POST',
      '/product-imports/$id/retry',
      expectedStatusCodes: const {HttpStatus.ok},
    );
    return ProductImportJobDto.fromJson(
      response as Map<String, dynamic>,
    ).toEntity();
  }

  Future<ProductImportJob> acknowledge(String id) async {
    final response = await _requestJson(
      'POST',
      '/product-imports/$id/acknowledge',
      expectedStatusCodes: const {HttpStatus.ok},
    );
    return ProductImportJobDto.fromJson(
      response as Map<String, dynamic>,
    ).toEntity();
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
      throw ProductImportApiException.fromResponse(
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
    final normalizedPath = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';
    return baseUri.replace(path: normalizedPath.isEmpty ? '/' : normalizedPath);
  }

  static String _trimmedPath(String path) {
    if (path.startsWith('/')) {
      return path.substring(1);
    }
    return path;
  }
}

class ProductImportJobDto {
  const ProductImportJobDto({
    required this.id,
    this.wishlistId,
    required this.clientRequestId,
    required this.normalizedUrl,
    required this.domain,
    required this.targetCurrencyCode,
    required this.status,
    required this.attemptCount,
    this.lastAttemptedAt,
    this.lastError,
    this.errorCode,
    required this.retryable,
    this.title,
    this.priceLabel,
    this.priceConfidence,
    this.priceSource,
    this.priceWarnings = const [],
    this.imageUrl,
    required this.completeness,
    this.progressStage,
    this.progressPercent = 0,
    this.createdItemId,
    this.acknowledgedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductImportJobDto.fromJson(Map<String, dynamic> json) {
    return ProductImportJobDto(
      id: json['id'] as String,
      wishlistId: json['wishlistId'] as String?,
      clientRequestId: json['clientRequestId'] as String,
      normalizedUrl: json['normalizedUrl'] as String,
      domain: json['domain'] as String,
      targetCurrencyCode: json['targetCurrencyCode'] as String? ?? 'USD',
      status: json['status'] as String,
      attemptCount: json['attemptCount'] as int? ?? 0,
      lastAttemptedAt: _optionalDate(json['lastAttemptedAt'] as String?),
      lastError: json['lastError'] as String?,
      errorCode: json['errorCode'] as String?,
      retryable: json['retryable'] as bool? ?? false,
      title: json['title'] as String?,
      priceLabel: json['priceLabel'] as String?,
      priceConfidence: json['priceConfidence'] as String?,
      priceSource: json['priceSource'] as String?,
      priceWarnings: (json['priceWarnings'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      imageUrl: json['imageUrl'] as String?,
      completeness: json['completeness'] as int? ?? 0,
      progressStage: json['progressStage'] as String?,
      progressPercent: json['progressPercent'] as int? ?? 0,
      createdItemId: json['createdItemId'] as String?,
      acknowledgedAt: _optionalDate(json['acknowledgedAt'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final String? wishlistId;
  final String clientRequestId;
  final String normalizedUrl;
  final String domain;
  final String targetCurrencyCode;
  final String status;
  final int attemptCount;
  final DateTime? lastAttemptedAt;
  final String? lastError;
  final String? errorCode;
  final bool retryable;
  final String? title;
  final String? priceLabel;
  final String? priceConfidence;
  final String? priceSource;
  final List<String> priceWarnings;
  final String? imageUrl;
  final int completeness;
  final String? progressStage;
  final int progressPercent;
  final String? createdItemId;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductImportJob toEntity() {
    return ProductImportJob(
      id: id,
      wishlistId: wishlistId,
      clientRequestId: clientRequestId,
      normalizedUrl: normalizedUrl,
      domain: domain,
      targetCurrencyCode: targetCurrencyCode,
      status: status,
      attemptCount: attemptCount,
      lastAttemptedAt: lastAttemptedAt,
      lastError: lastError,
      errorCode: errorCode,
      retryable: retryable,
      title: title,
      priceLabel: priceLabel,
      priceConfidence: priceConfidence,
      priceSource: priceSource,
      priceWarnings: priceWarnings,
      imageUrl: imageUrl,
      completeness: completeness,
      progressStage: progressStage,
      progressPercent: progressPercent,
      createdItemId: createdItemId,
      acknowledgedAt: acknowledgedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _optionalDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.parse(value);
  }
}

class ProductImportApiException implements IOException {
  const ProductImportApiException({
    required this.message,
    this.statusCode,
    this.code,
  });

  factory ProductImportApiException.fromResponse({
    required int statusCode,
    required String responseBody,
  }) {
    final fallbackMessage = 'Product import request failed ($statusCode).';
    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      return ProductImportApiException(
        message: error?['message'] as String? ?? fallbackMessage,
        statusCode: statusCode,
        code: error?['code'] as String?,
      );
    } catch (_) {
      return ProductImportApiException(
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
