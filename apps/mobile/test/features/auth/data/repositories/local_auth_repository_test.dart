import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/data/repositories/local_auth_repository.dart';
import 'package:wishiz/features/auth/data/storage/auth_storage.dart';

void main() {
  group('LocalAuthRepository', () {
    test('allows first signup when storage starts empty', () async {
      final storage = _FakeAuthStorage();
      final repository = await LocalAuthRepository.createWithStorage(storage);

      final result = await repository.signUp(
        email: 'first@example.com',
        password: 'password123',
        fullName: 'First User',
        birthday: DateTime(1990, 1, 1),
      );

      expect(result.isSuccess, isTrue);
      expect(repository.getCurrentUser()?.email, 'first@example.com');
    });

    test('signs up and persists the current user', () async {
      final storage = _FakeAuthStorage();
      final repository = await LocalAuthRepository.createWithStorage(storage);

      final result = await repository.signUp(
        email: 'dana@example.com',
        password: 'password123',
        fullName: 'Dana Rios',
        birthday: DateTime(1995, 5, 9),
      );

      expect(result.isSuccess, isTrue);
      expect(repository.getCurrentUser()?.fullName, 'Dana Rios');
      expect(repository.getCurrentUser()?.birthday, DateTime(1995, 5, 9));
      expect(repository.getCurrentUser()?.preferredCurrencyCode, 'USD');
      expect(repository.getCurrentUser()?.notificationsEnabled, isTrue);
      expect(repository.getCurrentUser()?.reminderDays, 14);
      expect(storage.value, contains('dana@example.com'));
      expect(storage.value, contains('1995-05-09'));
    });

    test('restores a signed up user on a new repository instance', () async {
      final storage = _FakeAuthStorage();
      final repository = await LocalAuthRepository.createWithStorage(storage);

      await repository.signUp(
        email: 'dana@example.com',
        password: 'password123',
        fullName: 'Dana Rios',
        birthday: DateTime(1995, 5, 9),
      );

      final reloadedRepository = await LocalAuthRepository.createWithStorage(
        storage,
      );

      expect(reloadedRepository.getCurrentUser(), isNotNull);
      expect(reloadedRepository.getCurrentUser()?.email, 'dana@example.com');
      expect(
          reloadedRepository.getCurrentUser()?.birthday, DateTime(1995, 5, 9));
    });

    test('updates the signed in user profile and persists settings', () async {
      final storage = _FakeAuthStorage();
      final repository = await LocalAuthRepository.createWithStorage(storage);

      await repository.signUp(
        email: 'dana@example.com',
        password: 'password123',
        fullName: 'Dana Rios',
        birthday: DateTime(1995, 5, 9),
      );

      final result = await repository.updateCurrentUser(
        email: 'daniela@example.com',
        fullName: 'Daniela Rios',
        birthday: DateTime(1994, 8, 14),
        preferredCurrencyCode: 'ILS',
        notificationsEnabled: false,
        reminderDays: 21,
        currentPassword: 'password123',
        newPassword: 'newpassword123',
      );

      expect(result.isSuccess, isTrue);
      expect(repository.getCurrentUser()?.email, 'daniela@example.com');
      expect(repository.getCurrentUser()?.fullName, 'Daniela Rios');
      expect(repository.getCurrentUser()?.birthday, DateTime(1994, 8, 14));
      expect(repository.getCurrentUser()?.preferredCurrencyCode, 'ILS');
      expect(repository.getCurrentUser()?.notificationsEnabled, isFalse);
      expect(repository.getCurrentUser()?.reminderDays, 21);
      expect(storage.value, contains('daniela@example.com'));
      expect(storage.value, contains('"preferredCurrencyCode":"ILS"'));
      expect(storage.value, contains('"reminderDays":21'));
      expect(storage.value, contains('"notificationsEnabled":false'));

      final reloadedRepository = await LocalAuthRepository.createWithStorage(
        storage,
      );
      expect(reloadedRepository.getCurrentUser()?.email, 'daniela@example.com');
      expect(reloadedRepository.getCurrentUser()?.preferredCurrencyCode, 'ILS');
      expect(
          reloadedRepository.getCurrentUser()?.notificationsEnabled, isFalse);
      expect(reloadedRepository.getCurrentUser()?.reminderDays, 21);

      await reloadedRepository.logOut();
      final loginResult = await reloadedRepository.logIn(
        email: 'daniela@example.com',
        password: 'newpassword123',
      );
      expect(loginResult.isSuccess, isTrue);
    });

    test('rejects updating the user email to one already in use', () async {
      final storage = _FakeAuthStorage();
      final repository = await LocalAuthRepository.createWithStorage(storage);

      await repository.signUp(
        email: 'first@example.com',
        password: 'password123',
        fullName: 'First User',
        birthday: DateTime(1990, 1, 1),
      );
      await repository.logOut();
      await repository.signUp(
        email: 'second@example.com',
        password: 'password123',
        fullName: 'Second User',
        birthday: DateTime(1991, 2, 2),
      );

      final result = await repository.updateCurrentUser(
        email: 'first@example.com',
        fullName: 'Second User',
        birthday: DateTime(1991, 2, 2),
        preferredCurrencyCode: 'USD',
        notificationsEnabled: true,
        reminderDays: 14,
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'An account with that email already exists.',
      );
      expect(repository.getCurrentUser()?.email, 'second@example.com');
    });

    test('returns a failure instead of throwing when storage write fails',
        () async {
      final storage = _FailingAuthStorage();
      final repository = await LocalAuthRepository.createWithStorage(storage);

      final result = await repository.signUp(
        email: 'dana@example.com',
        password: 'password123',
        fullName: 'Dana Rios',
        birthday: DateTime(1995, 5, 9),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'We could not save your account on this device.',
      );
      expect(repository.getCurrentUser(), isNull);
    });
  });
}

class _FakeAuthStorage implements AuthStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class _FailingAuthStorage implements AuthStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {
    throw Exception('write failed');
  }
}
