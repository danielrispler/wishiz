import 'package:flutter/foundation.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';

abstract class AuthRepository {
  ValueListenable<AppUser?> watchCurrentUser();

  AppUser? getCurrentUser();

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required DateTime birthday,
  });

  Future<AuthResult> logIn({
    required String email,
    required String password,
  });

  Future<AuthResult> updateCurrentUser({
    required String email,
    required String firstName,
    required String lastName,
    required DateTime birthday,
    required String preferredCurrencyCode,
    required bool notificationsEnabled,
    required int reminderDays,
    String? newPassword,
  });

  Future<void> logOut();
}
