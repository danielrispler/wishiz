abstract class AuthStorage {
  Future<String?> read();

  Future<void> write(String value);
}
