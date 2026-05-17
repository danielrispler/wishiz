import 'package:flutter/foundation.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';

abstract class AuthRepository {
  ValueListenable<AppUser?> watchCurrentUser();

  AppUser? getCurrentUser();

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
    String? gender,
  });

  Future<AuthResult> logIn({required String email, required String password});

  Future<AuthResult> updateCurrentUser({
    required String email,
    required String fullName,
    required DateTime birthday,
    String? gender,
    required String preferredCurrencyCode,
    required bool notificationsEnabled,
    required int reminderDays,
    String? currentPassword,
    String? newPassword,
  });

  Future<AuthResult> savePreferences({
    required List<String> brandNames,
    String? gender,
  });

  Future<void> logOut();
}

abstract class SessionTokenProvider {
  String? getSessionToken();
}
