import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:wishiz/features/auth/data/storage/auth_storage.dart';
import 'package:wishiz/features/auth/data/storage/shared_preferences_auth_storage.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository._(this._storage, this._storedUsers, this._currentUser)
      : _currentUserNotifier = ValueNotifier<AppUser?>(_currentUser);

  static final Uuid _uuid = Uuid();

  final AuthStorage _storage;
  final List<_StoredUser> _storedUsers;
  AppUser? _currentUser;
  final ValueNotifier<AppUser?> _currentUserNotifier;

  static Future<LocalAuthRepository> create() async {
    final storage = await SharedPreferencesAuthStorage.create();
    return createWithStorage(storage);
  }

  static Future<LocalAuthRepository> createWithStorage(
      AuthStorage storage) async {
    final source = await storage.read();
    final payload = _decode(source);
    final storedUsers = List<_StoredUser>.of(payload.users, growable: true);
    final currentUser = storedUsers
        .cast<_StoredUser?>()
        .firstWhere(
          (user) => user?.id == payload.currentUserId,
          orElse: () => null,
        )
        ?.toAppUser();

    return LocalAuthRepository._(storage, storedUsers, currentUser);
  }

  @override
  ValueListenable<AppUser?> watchCurrentUser() => _currentUserNotifier;

  @override
  AppUser? getCurrentUser() => _currentUser;

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final alreadyExists = _storedUsers.any(
      (user) => user.email.toLowerCase() == normalizedEmail,
    );
    if (alreadyExists) {
      return const AuthResult.failure(
          'An account with that email already exists.');
    }

    final storedUser = _StoredUser(
      id: _uuid.v4(),
      email: normalizedEmail,
      fullName: fullName.trim(),
      birthday: birthday,
      passwordHash: _hashPassword(password),
    );
    _storedUsers.add(storedUser);
    _setCurrentUser(storedUser.toAppUser());
    try {
      await _persist();
    } catch (_) {
      _storedUsers.removeWhere((user) => user.id == storedUser.id);
      _setCurrentUser(null);
      return const AuthResult.failure(
        'We could not save your account on this device.',
      );
    }
    return AuthResult.success(_currentUser!);
  }

  @override
  Future<AuthResult> logIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final passwordHash = _hashPassword(password);
    final matchedUser = _storedUsers.cast<_StoredUser?>().firstWhere(
          (user) =>
              user?.email.toLowerCase() == normalizedEmail &&
              user?.passwordHash == passwordHash,
          orElse: () => null,
        );

    if (matchedUser == null) {
      return const AuthResult.failure('Email or password is incorrect.');
    }

    _setCurrentUser(matchedUser.toAppUser());
    try {
      await _persist();
    } catch (_) {
      _setCurrentUser(null);
      return const AuthResult.failure(
        'We could not restore your session on this device.',
      );
    }
    return AuthResult.success(_currentUser!);
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
    final currentUser = _currentUser;
    if (currentUser == null) {
      return const AuthResult.failure('No account is signed in right now.');
    }

    final normalizedEmail = email.trim().toLowerCase();
    final alreadyExists = _storedUsers.any(
      (user) =>
          user.id != currentUser.id &&
          user.email.toLowerCase() == normalizedEmail,
    );
    if (alreadyExists) {
      return const AuthResult.failure(
          'An account with that email already exists.');
    }

    final index = _storedUsers.indexWhere((user) => user.id == currentUser.id);
    if (index == -1) {
      return const AuthResult.failure('We could not find that saved account.');
    }

    final existingUser = _storedUsers[index];
    final wantsToChangePassword = newPassword != null && newPassword.isNotEmpty;

    if (wantsToChangePassword) {
      final normalizedCurrentPassword = currentPassword?.trim() ?? '';
      if (normalizedCurrentPassword.isEmpty) {
        return const AuthResult.failure(
          'Enter your current password to set a new one.',
        );
      }

      if (_hashPassword(normalizedCurrentPassword) != existingUser.passwordHash) {
        return const AuthResult.failure('Current password is incorrect.');
      }
    }

    final updatedUser = existingUser.copyWith(
      email: normalizedEmail,
      fullName: fullName.trim(),
      birthday: birthday,
      preferredCurrencyCode: preferredCurrencyCode,
      notificationsEnabled: notificationsEnabled,
      reminderDays: reminderDays,
      passwordHash: wantsToChangePassword
          ? _hashPassword(newPassword)
          : existingUser.passwordHash,
    );

    _storedUsers[index] = updatedUser;
    _setCurrentUser(updatedUser.toAppUser());

    try {
      await _persist();
    } catch (_) {
      _storedUsers[index] = existingUser;
      _setCurrentUser(existingUser.toAppUser());
      return const AuthResult.failure(
        'We could not update your account on this device.',
      );
    }

    return AuthResult.success(_currentUser!);
  }

  @override
  Future<void> logOut() async {
    _setCurrentUser(null);
    await _persist();
  }

  void _setCurrentUser(AppUser? user) {
    _currentUser = user;
    _currentUserNotifier.value = user;
  }

  Future<void> _persist() async {
    final payload = _AuthPayload(
      currentUserId: _currentUser?.id,
      users: _storedUsers,
    );
    await _storage.write(jsonEncode(payload.toJson()));
  }

  static _AuthPayload _decode(String? source) {
    if (source == null || source.trim().isEmpty) {
      return _AuthPayload(
        currentUserId: null,
        users: <_StoredUser>[],
      );
    }

    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      final users = (json['users'] as List<dynamic>? ?? const [])
          .map((item) => _StoredUser.fromJson(item as Map<String, dynamic>))
          .toList(growable: true);
      return _AuthPayload(
        currentUserId: json['currentUserId'] as String?,
        users: users,
      );
    } on FormatException {
      return _AuthPayload(
        currentUserId: null,
        users: <_StoredUser>[],
      );
    } catch (_) {
      return _AuthPayload(
        currentUserId: null,
        users: <_StoredUser>[],
      );
    }
  }

  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }
}

class _AuthPayload {
  const _AuthPayload({
    required this.currentUserId,
    required this.users,
  });

  final String? currentUserId;
  final List<_StoredUser> users;

  Map<String, Object?> toJson() {
    return {
      'currentUserId': currentUserId,
      'users': users.map((user) => user.toJson()).toList(growable: false),
    };
  }
}

class _StoredUser {
  const _StoredUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.birthday,
    required this.passwordHash,
    this.preferredCurrencyCode = 'USD',
    this.notificationsEnabled = true,
    this.reminderDays = 14,
  });

  final String id;
  final String email;
  final String fullName;
  final DateTime birthday;
  final String passwordHash;
  final String preferredCurrencyCode;
  final bool notificationsEnabled;
  final int reminderDays;

  AppUser toAppUser() {
    return AppUser(
      id: id,
      email: email,
      fullName: fullName,
      birthday: birthday,
      preferredCurrencyCode: preferredCurrencyCode,
      notificationsEnabled: notificationsEnabled,
      reminderDays: reminderDays,
    );
  }

  _StoredUser copyWith({
    String? id,
    String? email,
    String? fullName,
    DateTime? birthday,
    String? passwordHash,
    String? preferredCurrencyCode,
    bool? notificationsEnabled,
    int? reminderDays,
  }) {
    return _StoredUser(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      birthday: birthday ?? this.birthday,
      passwordHash: passwordHash ?? this.passwordHash,
      preferredCurrencyCode:
          preferredCurrencyCode ?? this.preferredCurrencyCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      reminderDays: reminderDays ?? this.reminderDays,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'birthday': birthday.toIso8601String(),
      'passwordHash': passwordHash,
      'preferredCurrencyCode': preferredCurrencyCode,
      'notificationsEnabled': notificationsEnabled,
      'reminderDays': reminderDays,
    };
  }

  factory _StoredUser.fromJson(Map<String, dynamic> json) {
    final fallbackFirstName = json['firstName'] as String? ?? '';
    final fallbackLastName = json['lastName'] as String? ?? '';
    final fallbackFullName = '$fallbackFirstName $fallbackLastName'.trim();

    return _StoredUser(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: (json['fullName'] as String? ?? fallbackFullName).trim(),
      birthday: json['birthday'] != null
          ? DateTime.parse(json['birthday'] as String)
          : DateTime.now().subtract(const Duration(days: 365 * 18)),
      passwordHash: json['passwordHash'] as String,
      preferredCurrencyCode: json['preferredCurrencyCode'] as String? ?? 'USD',
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      reminderDays: json['reminderDays'] as int? ?? 14,
    );
  }
}
