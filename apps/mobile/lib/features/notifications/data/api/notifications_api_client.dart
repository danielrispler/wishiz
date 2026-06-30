import 'dart:convert';
import 'dart:io';

import 'package:wishiz/features/notifications/domain/entities/app_notification.dart';

class NotificationsApiClient {
  NotificationsApiClient({
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

  Future<List<AppNotification>> list({int limit = 50, int offset = 0}) async {
    final response = await _requestJson(
      'GET',
      '/notifications?limit=$limit&offset=$offset',
      expectedStatusCodes: const {HttpStatus.ok},
    );
    return (response as List<dynamic>)
        .map((entry) => _AppNotificationDto.fromJson(entry as Map<String, dynamic>).toEntity())
        .toList(growable: false);
  }

  Future<int> unreadCount() async {
    final response = await _requestJson(
      'GET',
      '/notifications/unread-count',
      expectedStatusCodes: const {HttpStatus.ok},
    );
    return (response as Map<String, dynamic>)['count'] as int? ?? 0;
  }

  Future<void> markRead(String id) async {
    await _requestJson(
      'POST',
      '/notifications/$id/read',
      expectedStatusCodes: const {HttpStatus.noContent},
    );
  }

  Future<void> markAllRead() async {
    await _requestJson(
      'POST',
      '/notifications/read-all',
      expectedStatusCodes: const {HttpStatus.ok},
    );
  }

  Future<void> registerDevice({required String token, required String platform}) async {
    await _requestJson(
      'POST',
      '/notifications/devices',
      body: {'token': token, 'platform': platform},
      expectedStatusCodes: const {HttpStatus.noContent},
    );
  }

  Future<void> deregisterDevice(String token) async {
    await _requestJson(
      'DELETE',
      '/notifications/devices',
      body: {'token': token},
      expectedStatusCodes: const {HttpStatus.noContent},
    );
  }

  Future<List<String>> listMutes() async {
    final response = await _requestJson(
      'GET',
      '/notifications/mutes',
      expectedStatusCodes: const {HttpStatus.ok},
    );
    final ids = (response as Map<String, dynamic>)['wishlistIds'] as List<dynamic>? ?? const [];
    return ids.whereType<String>().toList(growable: false);
  }

  Future<void> mute(String wishlistId) async {
    await _requestJson(
      'POST',
      '/notifications/mutes',
      body: {'wishlistId': wishlistId},
      expectedStatusCodes: const {HttpStatus.noContent},
    );
  }

  Future<void> unmute(String wishlistId) async {
    await _requestJson(
      'DELETE',
      '/notifications/mutes/$wishlistId',
      expectedStatusCodes: const {HttpStatus.noContent},
    );
  }

  Future<dynamic> _requestJson(
    String method,
    String path, {
    Object? body,
    required Set<int> expectedStatusCodes,
  }) async {
    final request = await _httpClient.openUrl(method, _baseUri.resolve(_trimmedPath(path)));
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_authToken');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (!expectedStatusCodes.contains(response.statusCode)) {
      throw NotificationsApiException.fromResponse(
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
    final normalizedPath = baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
    return baseUri.replace(path: normalizedPath.isEmpty ? '/' : normalizedPath);
  }

  static String _trimmedPath(String path) {
    if (path.startsWith('/')) {
      return path.substring(1);
    }
    return path;
  }
}

class _AppNotificationDto {
  const _AppNotificationDto({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.wishlistId,
    this.itemId,
    this.importJobId,
    this.readAt,
    required this.createdAt,
  });

  factory _AppNotificationDto.fromJson(Map<String, dynamic> json) {
    return _AppNotificationDto(
      id: json['id'] as String,
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      wishlistId: json['wishlistId'] as String?,
      itemId: json['itemId'] as String?,
      importJobId: json['importJobId'] as String?,
      readAt: _optionalDate(json['readAt'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final String? wishlistId;
  final String? itemId;
  final String? importJobId;
  final DateTime? readAt;
  final DateTime createdAt;

  AppNotification toEntity() {
    return AppNotification(
      id: id,
      type: notificationTypeFromString(type),
      title: title,
      body: body,
      wishlistId: wishlistId,
      itemId: itemId,
      importJobId: importJobId,
      readAt: readAt,
      createdAt: createdAt,
    );
  }

  static DateTime? _optionalDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.parse(value);
  }
}

class NotificationsApiException implements IOException {
  const NotificationsApiException({required this.message, this.statusCode, this.code});

  factory NotificationsApiException.fromResponse({
    required int statusCode,
    required String responseBody,
  }) {
    final fallbackMessage = 'Notification request failed ($statusCode).';
    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      return NotificationsApiException(
        message: error?['message'] as String? ?? fallbackMessage,
        statusCode: statusCode,
        code: error?['code'] as String?,
      );
    } catch (_) {
      return NotificationsApiException(message: fallbackMessage, statusCode: statusCode);
    }
  }

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}
