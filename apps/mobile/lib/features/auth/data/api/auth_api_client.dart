import 'dart:convert';
import 'dart:io';

import 'package:wishiz/features/auth/domain/entities/app_user.dart';

class AuthApiClient {
  AuthApiClient({required Uri baseUri, HttpClient? httpClient})
    : _baseUri = _normalizeBaseUri(baseUri),
      _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  final Uri _baseUri;
  final HttpClient _httpClient;

  Future<AuthSessionDto> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
  }) async {
    final response = await _requestJson(
      'POST',
      '/auth/signup',
      body: {
        'email': email,
        'password': password,
        'fullName': fullName,
        'birthday': birthday.toUtc().toIso8601String(),
      },
      expectedStatusCodes: const {HttpStatus.created},
    );

    return AuthSessionDto.fromJson(response as Map<String, dynamic>);
  }

  Future<AuthSessionDto> logIn({
    required String email,
    required String password,
  }) async {
    final response = await _requestJson(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return AuthSessionDto.fromJson(response as Map<String, dynamic>);
  }

  Future<AppUserDto> getCurrentUser({required String authToken}) async {
    final response = await _requestJson(
      'GET',
      '/auth/me',
      authToken: authToken,
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return AppUserDto.fromJson(response as Map<String, dynamic>);
  }

  Future<AppUserDto> updateCurrentUser({
    required String authToken,
    required String email,
    required String fullName,
    required DateTime birthday,
    required String preferredCurrencyCode,
    required bool notificationsEnabled,
    required int reminderDays,
    String? currentPassword,
    String? newPassword,
  }) async {
    final response = await _requestJson(
      'PATCH',
      '/auth/me',
      authToken: authToken,
      body: {
        'email': email,
        'fullName': fullName,
        'birthday': birthday.toUtc().toIso8601String(),
        'preferredCurrencyCode': preferredCurrencyCode,
        'notificationsEnabled': notificationsEnabled,
        'reminderDays': reminderDays,
        'currentPassword': currentPassword ?? '',
        'newPassword': newPassword ?? '',
      },
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return AppUserDto.fromJson(response as Map<String, dynamic>);
  }

  Future<AppUserDto> updatePreferences({
    required String authToken,
    required List<String> brandNames,
  }) async {
    final response = await _requestJson(
      'PATCH',
      '/auth/me/onboarding',
      authToken: authToken,
      body: {'brands': brandNames},
      expectedStatusCodes: const {HttpStatus.ok},
    );

    return AppUserDto.fromJson(response as Map<String, dynamic>);
  }

  Future<void> logOut({required String authToken}) {
    return _requestJson(
      'POST',
      '/auth/logout',
      authToken: authToken,
      expectedStatusCodes: const {HttpStatus.noContent},
    );
  }

  Future<dynamic> _requestJson(
    String method,
    String path, {
    String? authToken,
    Object? body,
    required Set<int> expectedStatusCodes,
  }) async {
    final request = await _httpClient.openUrl(
      method,
      _baseUri.resolve(_trimmedPath(path)),
    );
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (authToken != null && authToken.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (!expectedStatusCodes.contains(response.statusCode)) {
      throw AuthApiException.fromResponse(
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

class AuthSessionDto {
  const AuthSessionDto({required this.token, required this.user});

  factory AuthSessionDto.fromJson(Map<String, dynamic> json) {
    return AuthSessionDto(
      token: json['token'] as String,
      user: AppUserDto.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  final String token;
  final AppUserDto user;
}

class AppUserDto {
  const AppUserDto({
    required this.id,
    required this.email,
    required this.fullName,
    required this.birthday,
    required this.preferredCurrencyCode,
    required this.notificationsEnabled,
    required this.reminderDays,
    required this.preferredBrands,
  });

  factory AppUserDto.fromJson(Map<String, dynamic> json) {
    return AppUserDto(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String,
      birthday: DateTime.parse(json['birthday'] as String),
      preferredCurrencyCode: json['preferredCurrencyCode'] as String? ?? 'USD',
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      reminderDays: json['reminderDays'] as int? ?? 14,
      preferredBrands:
          (json['preferredBrands'] as List<dynamic>?)?.cast<String>() ??
          const [],
    );
  }

  final String id;
  final String email;
  final String fullName;
  final DateTime birthday;
  final String preferredCurrencyCode;
  final bool notificationsEnabled;
  final int reminderDays;
  final List<String> preferredBrands;

  AppUser toEntity() {
    return AppUser(
      id: id,
      email: email,
      fullName: fullName,
      birthday: birthday,
      preferredCurrencyCode: preferredCurrencyCode,
      notificationsEnabled: notificationsEnabled,
      reminderDays: reminderDays,
      preferredBrands: preferredBrands,
    );
  }
}

class AuthApiException implements IOException {
  const AuthApiException({
    required this.statusCode,
    required this.message,
    this.field,
  });

  factory AuthApiException.fromResponse({
    required int statusCode,
    required String responseBody,
  }) {
    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>;
      return AuthApiException(
        statusCode: statusCode,
        message:
            error['message'] as String? ?? 'Authentication request failed.',
        field: error['field'] as String?,
      );
    } catch (_) {
      return AuthApiException(
        statusCode: statusCode,
        message: 'Authentication request failed.',
      );
    }
  }

  final int statusCode;
  final String message;
  final String? field;

  @override
  String toString() =>
      'AuthApiException(statusCode: $statusCode, message: $message, field: $field)';
}
