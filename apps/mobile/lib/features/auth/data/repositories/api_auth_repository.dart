import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wishiz/features/auth/data/api/auth_api_client.dart';
import 'package:wishiz/features/auth/data/storage/auth_storage.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';

class ApiAuthRepository implements AuthRepository, SessionTokenProvider {
  ApiAuthRepository._(
    this._storage,
    this._apiClient,
    this._currentUser,
    this._sessionToken,
  ) : _currentUserNotifier = ValueNotifier<AppUser?>(_currentUser);

  final AuthStorage _storage;
  final AuthApiClient _apiClient;
  AppUser? _currentUser;
  String? _sessionToken;
  final ValueNotifier<AppUser?> _currentUserNotifier;

  static Future<ApiAuthRepository> create({
    required AuthStorage storage,
    required AuthApiClient apiClient,
  }) async {
    final payload = _decode(await storage.read());
    final repository = ApiAuthRepository._(
      storage,
      apiClient,
      payload?.user,
      payload?.token,
    );

    if (repository._sessionToken != null) {
      try {
        final currentUser = await apiClient.getCurrentUser(
          authToken: repository._sessionToken!,
        );
        repository._setSession(
          user: currentUser.toEntity(),
          token: repository._sessionToken!,
        );
        await repository._persist();
      } on AuthApiException catch (error) {
        if (error.statusCode == 401) {
          repository._clearSession();
          await repository._persist();
        } else {
          rethrow;
        }
      }
    }

    return repository;
  }

  @override
  ValueListenable<AppUser?> watchCurrentUser() => _currentUserNotifier;

  @override
  AppUser? getCurrentUser() => _currentUser;

  @override
  String? getSessionToken() => _sessionToken;

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
  }) async {
    try {
      final session = await _apiClient.signUp(
        email: email,
        password: password,
        fullName: fullName,
        birthday: birthday,
      );
      _setSession(user: session.user.toEntity(), token: session.token);
      await _persist();
      return AuthResult.success(_currentUser!);
    } on AuthApiException catch (error) {
      return AuthResult.failure(error.message);
    }
  }

  @override
  Future<AuthResult> logIn({
    required String email,
    required String password,
  }) async {
    try {
      final session = await _apiClient.logIn(email: email, password: password);
      _setSession(user: session.user.toEntity(), token: session.token);
      await _persist();
      return AuthResult.success(_currentUser!);
    } on AuthApiException catch (error) {
      return AuthResult.failure(error.message);
    }
  }

  @override
  Future<AuthResult> updateCurrentUser({
    required String email,
    required String fullName,
    required DateTime birthday,
    required String preferredCurrencyCode,
    required bool notificationsEnabled,
    required int reminderDays,
    String? currentPassword,
    String? newPassword,
  }) async {
    if (_sessionToken == null) {
      return const AuthResult.failure('No account is signed in right now.');
    }

    try {
      final user = await _apiClient.updateCurrentUser(
        authToken: _sessionToken!,
        email: email,
        fullName: fullName,
        birthday: birthday,
        preferredCurrencyCode: preferredCurrencyCode,
        notificationsEnabled: notificationsEnabled,
        reminderDays: reminderDays,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _setSession(user: user.toEntity(), token: _sessionToken!);
      await _persist();
      return AuthResult.success(_currentUser!);
    } on AuthApiException catch (error) {
      if (error.statusCode == 401) {
        _clearSession();
        await _persist();
      }
      return AuthResult.failure(error.message);
    }
  }

  @override
  Future<void> logOut() async {
    final token = _sessionToken;
    _clearSession();
    await _persist();
    if (token == null) {
      return;
    }

    try {
      await _apiClient.logOut(authToken: token);
    } catch (_) {
      // The local session is already gone; do not block logout on network cleanup.
    }
  }

  void _setSession({required AppUser user, required String token}) {
    _currentUser = user;
    _sessionToken = token;
    _currentUserNotifier.value = user;
  }

  void _clearSession() {
    _currentUser = null;
    _sessionToken = null;
    _currentUserNotifier.value = null;
  }

  Future<void> _persist() async {
    await _storage.write(
      jsonEncode(
        _StoredSessionPayload(
          token: _sessionToken,
          user: _currentUser,
        ).toJson(),
      ),
    );
  }

  static _StoredSessionPayload? _decode(String? source) {
    if (source == null || source.trim().isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      return _StoredSessionPayload.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

class _StoredSessionPayload {
  const _StoredSessionPayload({required this.token, required this.user});

  factory _StoredSessionPayload.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    return _StoredSessionPayload(
      token: json['token'] as String?,
      user: userJson is Map<String, dynamic>
          ? AppUserDto.fromJson(userJson).toEntity()
          : null,
    );
  }

  final String? token;
  final AppUser? user;

  Map<String, Object?> toJson() {
    return {
      'token': token,
      'user': user == null
          ? null
          : {
              'id': user!.id,
              'email': user!.email,
              'fullName': user!.fullName,
              'birthday': user!.birthday.toUtc().toIso8601String(),
              'preferredCurrencyCode': user!.preferredCurrencyCode,
              'notificationsEnabled': user!.notificationsEnabled,
              'reminderDays': user!.reminderDays,
            },
    };
  }
}
