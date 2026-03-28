import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/data/repositories/local_auth_repository.dart';
import 'package:wishiz/features/auth/data/storage/auth_storage.dart';

void main() {
  test('allows temporary daniel login for local testing', () async {
    final storage = _FakeAuthStorage();
    final repository = await LocalAuthRepository.createWithStorage(storage);

    final result = await repository.logIn(
      email: 'daniel',
      password: 'daniel',
    );

    expect(result.isSuccess, isTrue);
    expect(repository.getCurrentUser()?.email, 'daniel@wishiz.local');
    expect(repository.getCurrentUser()?.fullName, 'Daniel Daniel');
    expect(storage.value, contains('daniel@wishiz.local'));
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
