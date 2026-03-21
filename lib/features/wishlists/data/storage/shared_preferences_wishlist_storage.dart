import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishiz/features/wishlists/data/storage/wishlist_storage.dart';

class SharedPreferencesWishlistStorage implements WishlistStorage {
  SharedPreferencesWishlistStorage._(this._preferences);

  static const String _storageKey = 'wishiz.wishlists';

  final SharedPreferences _preferences;

  static Future<SharedPreferencesWishlistStorage> create() async {
    final preferences = await SharedPreferences.getInstance();
    return SharedPreferencesWishlistStorage._(preferences);
  }

  @override
  Future<String?> read() async => _preferences.getString(_storageKey);

  @override
  Future<void> write(String value) async {
    await _preferences.setString(_storageKey, value);
  }
}
