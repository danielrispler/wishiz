import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/screens/signup/signup_screen.dart';

void main() {
  testWidgets('shows the selected birthday in a readable format', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: SignupScreen(
          authRepository: authRepository,
          onShowLogin: () {},
          showBirthdayPicker: (context, initialDate) async {
            return DateTime(1995, 5, 9);
          },
        ),
      ),
    );

    await tester.tap(find.byType(TextFormField).at(1));
    await tester.pumpAndSettle();

    expect(find.text('1995-05-09'), findsOneWidget);
  });

  testWidgets('submits signup data when the form is valid', (tester) async {
    final authRepository = _FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: SignupScreen(
          authRepository: authRepository,
          onShowLogin: () {},
          showBirthdayPicker: (context, initialDate) async {
            return DateTime(1995, 5, 9);
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'Dana Rios');
    await tester.tap(find.byType(TextFormField).at(1));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'dana@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(3), 'password123');
    await tester.enterText(find.byType(TextFormField).at(4), 'password123');

    final signUpButton = find.byType(ElevatedButton);
    await tester.scrollUntilVisible(
      signUpButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(signUpButton);
    await tester.pumpAndSettle();

    expect(authRepository.signUpCalls, hasLength(1));
    expect(authRepository.signUpCalls.single.fullName, 'Dana Rios');
    expect(authRepository.signUpCalls.single.email, 'dana@example.com');
    expect(authRepository.signUpCalls.single.birthday, DateTime(1995, 5, 9));
  });
}

class _FakeAuthRepository implements AuthRepository {
  final ValueNotifier<AppUser?> _currentUser = ValueNotifier<AppUser?>(null);
  final List<_SignUpCall> signUpCalls = [];

  @override
  AppUser? getCurrentUser() => _currentUser.value;

  @override
  Future<AuthResult> logIn({
    required String email,
    required String password,
  }) async {
    return const AuthResult.failure('Not implemented in test.');
  }

  @override
  Future<AuthResult> savePreferences({
    required List<String> brandNames,
  }) async => AuthResult.success(getCurrentUser()!);

  @override
  Future<void> logOut() async {}

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
  }) async {
    signUpCalls.add(
      _SignUpCall(
        email: email,
        password: password,
        fullName: fullName,
        birthday: birthday,
      ),
    );
    final user = AppUser(
      id: 'user-1',
      email: email,
      fullName: fullName,
      birthday: birthday,
    );
    _currentUser.value = user;
    return AuthResult.success(user);
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

class _SignUpCall {
  const _SignUpCall({
    required this.email,
    required this.password,
    required this.fullName,
    required this.birthday,
  });

  final String email;
  final String password;
  final String fullName;
  final DateTime birthday;
}
