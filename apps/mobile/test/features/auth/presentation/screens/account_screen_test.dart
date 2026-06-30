import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/screens/account/account_screen.dart';

void main() {
  testWidgets('renders without a birthday and never requires one', (
    tester,
  ) async {
    final repo = _FakeAuthRepository(_userWithoutBirthday());

    await tester.pumpWidget(
      MaterialApp(home: AccountScreen(authRepository: repo)),
    );
    await tester.pumpAndSettle();

    // The field is optional and prompts to add one rather than demanding it.
    expect(find.text('Birthday (optional)'), findsOneWidget);
    expect(find.text('Add your birthday'), findsOneWidget);
  });

  testWidgets('clears an existing birthday and saves it as null', (
    tester,
  ) async {
    final repo = _FakeAuthRepository(_userWithBirthday());

    await tester.pumpWidget(
      MaterialApp(home: AccountScreen(authRepository: repo)),
    );
    await tester.pumpAndSettle();

    // The clear affordance is present because a birthday is set.
    final clearButton = find.byTooltip('Clear birthday');
    expect(clearButton, findsOneWidget);
    await tester.ensureVisible(clearButton);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    // Field empties and the clear affordance is replaced by the calendar prompt.
    expect(find.text('Add your birthday'), findsOneWidget);
    expect(find.byTooltip('Clear birthday'), findsNothing);

    final saveButton = find.widgetWithText(ElevatedButton, 'Save changes');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repo.updateCalls, hasLength(1));
    expect(repo.updateCalls.single, isNull);
  });

  testWidgets('delete account requires the password and calls the repo', (
    tester,
  ) async {
    final repo = _FakeAuthRepository(_userWithoutBirthday());

    await tester.pumpWidget(
      MaterialApp(home: AccountScreen(authRepository: repo)),
    );
    await tester.pumpAndSettle();

    final deleteButton = find.widgetWithText(TextButton, 'Delete account');
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    // Confirmation dialog warns and asks for the password.
    expect(find.text('Delete account?'), findsOneWidget);
    expect(find.textContaining('removed for everyone'), findsOneWidget);

    // Confirming with no password surfaces an inline error, no call made.
    await tester.tap(find.widgetWithText(TextButton, 'Delete account').last);
    await tester.pumpAndSettle();
    expect(repo.deleteAccountCalls, isEmpty);
    expect(find.text('Enter your password to confirm.'), findsOneWidget);

    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, 'hunter2');
    await tester.tap(find.widgetWithText(TextButton, 'Delete account').last);
    await tester.pumpAndSettle();

    expect(repo.deleteAccountCalls, ['hunter2']);
  });
}

AppUser _userWithoutBirthday() {
  return const AppUser(
    id: 'user-1',
    email: 'maya@example.com',
    fullName: 'Maya Hope',
    birthday: null,
  );
}

AppUser _userWithBirthday() {
  return AppUser(
    id: 'user-1',
    email: 'maya@example.com',
    fullName: 'Maya Hope',
    birthday: DateTime(1990, 5, 5),
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(AppUser user)
    : _currentUser = ValueNotifier<AppUser?>(user);

  final ValueNotifier<AppUser?> _currentUser;
  final List<String> deleteAccountCalls = [];
  final List<DateTime?> updateCalls = [];

  @override
  AppUser? getCurrentUser() => _currentUser.value;

  @override
  ValueListenable<AppUser?> watchCurrentUser() => _currentUser;

  @override
  Future<void> deleteAccount({required String password}) async {
    deleteAccountCalls.add(password);
    _currentUser.value = null;
  }

  @override
  Future<void> logOut() async {
    _currentUser.value = null;
  }

  @override
  Future<AuthResult> logIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AuthResult> savePreferences({
    required List<String> brandNames,
    String? gender,
  }) => throw UnimplementedError();

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    DateTime? birthday,
    String? gender,
  }) => throw UnimplementedError();

  @override
  Future<AuthResult> updateCurrentUser({
    required String email,
    required String fullName,
    DateTime? birthday,
    String? gender,
    required String preferredCurrencyCode,
    required bool notificationsEnabled,
    required int reminderDays,
    String? currentPassword,
    String? newPassword,
  }) async {
    updateCalls.add(birthday);
    final current = _currentUser.value!;
    final updated = AppUser(
      id: current.id,
      email: email,
      fullName: fullName,
      birthday: birthday,
      gender: gender,
      preferredCurrencyCode: preferredCurrencyCode,
      notificationsEnabled: notificationsEnabled,
      reminderDays: reminderDays,
      preferredBrands: current.preferredBrands,
    );
    _currentUser.value = updated;
    return AuthResult.success(updated);
  }
}
