import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/screens/login/login_screen.dart';

void main() {
  testWidgets('submits login data when the form is valid', (tester) async {
    final authRepository = _FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          authRepository: authRepository,
          onShowSignUp: () {},
        ),
      ),
    );

    await tester.enterText(
        find.byType(TextFormField).at(0), 'dana@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');

    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(authRepository.loginCalls, hasLength(1));
    expect(authRepository.loginCalls.single.email, 'dana@example.com');
    expect(authRepository.loginCalls.single.password, 'password123');
  });
}

class _FakeAuthRepository implements AuthRepository {
  final ValueNotifier<AppUser?> _currentUser = ValueNotifier<AppUser?>(null);
  final List<_LoginCall> loginCalls = [];

  @override
  AppUser? getCurrentUser() => _currentUser.value;

  @override
  Future<AuthResult> logIn({
    required String email,
    required String password,
  }) async {
    loginCalls.add(
      _LoginCall(
        email: email,
        password: password,
      ),
    );
    final user = AppUser(
      id: 'user-1',
      email: email,
      fullName: 'Dana Rios',
      birthday: DateTime(1995, 5, 9),
    );
    _currentUser.value = user;
    return AuthResult.success(user);
  }

  @override
  Future<AuthResult> saveOnboardingCategories(List<String> categoryIds) async =>
      AuthResult.success(getCurrentUser()!);

  @override
  Future<void> logOut() async {}

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
  }) async {
    return const AuthResult.failure('Not implemented in test.');
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
    return const AuthResult.failure('Not implemented in test.');
  }

  @override
  ValueListenable<AppUser?> watchCurrentUser() => _currentUser;
}

class _LoginCall {
  const _LoginCall({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}
