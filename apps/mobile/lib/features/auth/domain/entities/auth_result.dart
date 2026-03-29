import 'package:wishiz/features/auth/domain/entities/app_user.dart';

class AuthResult {
  const AuthResult._({
    this.user,
    this.errorMessage,
  });

  const AuthResult.success(AppUser user) : this._(user: user);

  const AuthResult.failure(String errorMessage)
      : this._(errorMessage: errorMessage);

  final AppUser? user;
  final String? errorMessage;

  bool get isSuccess => user != null && errorMessage == null;
}
