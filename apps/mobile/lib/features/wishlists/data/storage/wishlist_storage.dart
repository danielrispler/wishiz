abstract class WishlistStorage {
  Future<String?> read();

  Future<void> write(String value);
}
