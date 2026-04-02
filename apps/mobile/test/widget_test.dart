import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';

void main() {
  test('app user exposes the preferred currency symbol', () {
    final user = AppUser(
      id: 'user-1',
      email: 'dana@example.com',
      fullName: 'Dana Rios',
      birthday: DateTime(1995, 5, 9),
      preferredCurrencyCode: 'ILS',
    );

    expect(user.preferredCurrencySymbol, '₪');
  });
}
